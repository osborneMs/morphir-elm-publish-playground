module Morphir.Visual.ViewValue exposing (viewDefinition, viewValue)

import Dict
import Element exposing (Element, column, el, fill, htmlAttribute, padding, rgb, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Events exposing (onClick, onMouseEnter, onMouseLeave)
import Element.Font as Font exposing (..)
import Html.Attributes exposing (style)
import Morphir.IR.FQName exposing (FQName, getLocalName)
import Morphir.IR.Name exposing (Name, toCamelCase)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Basics as Basics
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue, Value(..))
import Morphir.Type.Infer as Infer exposing (TypeError)
import Morphir.Visual.BoolOperatorTree as BoolOperatorTree exposing (BoolOperatorTree)
import Morphir.Visual.Common exposing (definition, nameToText)
import Morphir.Visual.Components.AritmeticExpressions as ArithmeticOperatorTree exposing (ArithmeticOperatorTree)
import Morphir.Visual.Config as Config exposing (Config)
import Morphir.Visual.EnrichedValue exposing (EnrichedValue, fromRawValue, fromTypedValue)
import Morphir.Visual.Theme exposing (mediumPadding, mediumSpacing, smallPadding, smallSpacing)
import Morphir.Visual.ViewApply as ViewApply
import Morphir.Visual.ViewArithmetic as ViewArithmetic
import Morphir.Visual.ViewBoolOperatorTree as ViewBoolOperatorTree
import Morphir.Visual.ViewDestructure as ViewDestructure
import Morphir.Visual.ViewIfThenElse as ViewIfThenElse
import Morphir.Visual.ViewLambda as ViewLambda
import Morphir.Visual.ViewList as ViewList
import Morphir.Visual.ViewLiteral as ViewLiteral
import Morphir.Visual.ViewPatternMatch as ViewPatternMatch
import Morphir.Visual.ViewRecord as ViewRecord
import Morphir.Visual.XRayView as XRayView


viewDefinition : Config msg -> FQName -> Value.Definition () (Type ()) -> Element msg
viewDefinition config ( packageName, moduleName, valueName ) valueDef =
    let
        definitionElem =
            definition config
                (nameToText valueName)
                (viewValue config (valueDef.body |> fromTypedValue))
    in
    Element.column [ mediumSpacing config.state.theme |> spacing ]
        [ definitionElem
        , if Dict.isEmpty config.state.expandedFunctions then
            Element.none

          else
            Element.column
                [ mediumSpacing config.state.theme |> spacing ]
                (config.state.expandedFunctions
                    |> Dict.toList
                    |> List.reverse
                    |> List.map
                        (\( ( _, _, localName ) as fqName, valDef ) ->
                            Element.column
                                [ smallSpacing config.state.theme |> spacing ]
                                [ definition config (nameToText localName) (viewValue config (valDef.body |> fromTypedValue))
                                , Element.el
                                    [ Font.bold
                                    , Border.solid
                                    , Border.rounded 3
                                    , Background.color config.state.theme.colors.lightest
                                    , Font.color config.state.theme.colors.darkest
                                    , smallPadding config.state.theme |> padding
                                    , smallSpacing config.state.theme |> spacing
                                    , onClick (config.handlers.onReferenceClicked fqName True)
                                    ]
                                    (Element.text "Close")
                                ]
                        )
                )
        ]


viewValue : Config msg -> EnrichedValue -> Element msg
viewValue config typedValue =
    let
        valueType : Type ()
        valueType =
            Value.valueAttribute typedValue |> Tuple.second
    in
    if valueType == Basics.boolType () then
        let
            boolOperatorTree : BoolOperatorTree
            boolOperatorTree =
                BoolOperatorTree.fromTypedValue typedValue
        in
        ViewBoolOperatorTree.view config (viewValueByLanguageFeature config) boolOperatorTree

    else if Basics.isNumber valueType then
        let
            arithmeticOperatorTree : ArithmeticOperatorTree
            arithmeticOperatorTree =
                ArithmeticOperatorTree.fromArithmeticTypedValue typedValue
        in
        ViewArithmetic.view config (viewValueByLanguageFeature config) arithmeticOperatorTree

    else
        viewValueByLanguageFeature config typedValue


viewValueByLanguageFeature : Config msg -> EnrichedValue -> Element msg
viewValueByLanguageFeature config value =
    let
        valueElem : Element msg
        valueElem =
            case value of
                Value.Literal _ literal ->
                    ViewLiteral.view config literal

                Value.Constructor _ (( _, _, localName ) as fQName) ->
                    case fQName of
                        ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], _ ) ->
                            Element.none

                        ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] ) ->
                            Element.none

                        ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ) ->
                            el [Element.centerY ] (text " - ")

                        _ ->
                            Element.row
                                [ smallPadding config.state.theme |> padding
                                , smallSpacing config.state.theme |> spacing
                                , onClick (config.handlers.onReferenceClicked fQName False)
                                ]
                                [ text (nameToText localName) ]

                Value.Tuple _ elems ->
                    column
                        [ mediumSpacing config.state.theme |> spacing
                        ]
                        [ Element.row
                            [ mediumSpacing config.state.theme |> spacing
                            , smallPadding config.state.theme |> padding
                            ]
                            [ text "("
                            , elems
                                |> List.map (viewValue config)
                                |> List.intersperse (text ",")
                                |> Element.row [ smallSpacing config.state.theme |> spacing ]
                            , text ")"
                            ]
                        ]

                Value.List ( _, Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "list" ] ) [ itemType ] ) items ->
                    ViewList.view config (viewValue config) itemType items

                Value.Record _ items ->
                    ViewRecord.view config (viewValue config) items

                Value.Variable ( index, _ ) name ->
                    let
                        variableValue : Maybe RawValue
                        variableValue =
                            Dict.get name config.state.variables
                    in
                    el
                        [ onMouseEnter (config.handlers.onHoverOver index variableValue)
                        , onMouseLeave (config.handlers.onHoverLeave index)
                        , Element.below
                            (if config.state.popupVariables.variableIndex == index then
                                el [ smallPadding config.state.theme |> padding ] (viewPopup config)

                             else
                                Element.none
                            )
                        , center
                        ]
                        (text (nameToText name))

                Value.Reference _ (( _, _, localName ) as fQName) ->
                    Element.row
                        [ smallPadding config.state.theme |> padding
                        , smallSpacing config.state.theme |> spacing
                        , onClick (config.handlers.onReferenceClicked fQName False)
                        ]
                        [ text (nameToText localName) ]

                Value.Field ( _, _ ) subjectValue fieldName ->
                    let
                        defaultValue =
                            Element.row
                                [ smallPadding config.state.theme |> padding, spacing 1, alignLeft ]
                                [ viewValue config subjectValue
                                , el [ Font.bold ] (text ".")
                                , text (toCamelCase fieldName)
                                ]
                    in
                    case Config.evaluate (subjectValue |> Value.toRawValue) config of
                        Ok valueType ->
                            case valueType |> fromRawValue config.ir of
                                Ok (Value.Variable ( index, _ ) variableName) ->
                                    let
                                        variableValue : Maybe RawValue
                                        variableValue =
                                            Dict.get variableName config.state.variables
                                    in
                                    el
                                        [ onMouseEnter (config.handlers.onHoverOver index variableValue)
                                        , onMouseLeave (config.handlers.onHoverLeave index)
                                        , Element.below
                                            (if config.state.popupVariables.variableIndex == index then
                                                el [ smallPadding config.state.theme |> padding ] (viewPopup config)

                                             else
                                                Element.text "Not Found"
                                            )
                                        , center
                                        ]
                                        (String.concat
                                            [ "the "
                                            , nameToText variableName
                                            , "'s "
                                            , nameToText fieldName
                                            ]
                                            |> text
                                        )

                                _ ->
                                    defaultValue

                        Err _ ->
                            defaultValue

                Value.Apply _ fun arg ->
                    let
                        ( function, args ) =
                            Value.uncurryApply fun arg
                    in
                    ViewApply.view config (viewValue config) function args

                Value.LetDefinition _ _ _ _ ->
                    let
                        unnest : Config msg -> EnrichedValue -> ( List ( Name, Element msg ), Element msg )
                        unnest conf v =
                            case v of
                                Value.LetDefinition _ defName def inVal ->
                                    let
                                        currentState =
                                            conf.state

                                        newState =
                                            { currentState
                                                | variables =
                                                    conf
                                                        |> Config.evaluate
                                                            (def
                                                                |> Value.mapDefinitionAttributes (always ()) (always ())
                                                                |> Value.definitionToValue
                                                            )
                                                        |> Result.map
                                                            (\evaluatedDefValue ->
                                                                currentState.variables
                                                                    |> Dict.insert defName evaluatedDefValue
                                                            )
                                                        |> Result.withDefault currentState.variables
                                            }

                                        ( defs, bottomIn ) =
                                            unnest { conf | state = newState } inVal
                                    in
                                    ( ( defName, viewValue conf def.body ) :: defs, bottomIn )

                                notLet ->
                                    ( [], viewValue conf notLet )

                        ( definitions, inValueElem ) =
                            unnest config value
                    in
                    Element.column
                        [ mediumSpacing config.state.theme |> spacing ]
                        [ inValueElem
                        , Element.column
                            [ mediumSpacing config.state.theme |> spacing ]
                            (definitions
                                |> List.map
                                    (\( defName, defElem ) ->
                                        Element.column
                                            [ mediumSpacing config.state.theme |> spacing ]
                                            [ definition config (nameToText defName) defElem ]
                                    )
                            )
                        ]

                Value.IfThenElse _ _ _ _ ->
                    ViewIfThenElse.view config viewValue value

                Value.PatternMatch _ param patterns ->
                    ViewPatternMatch.view config viewValue param patterns

                Value.Lambda _ pattern param ->
                    ViewLambda.view config viewValue pattern param

                Value.FieldFunction _ name ->
                    text <| "." ++ toCamelCase name

                Value.Unit _ ->
                    el [ Element.centerX, Element.centerY, smallPadding config.state.theme |> padding ] (text "not set")

                Value.UpdateRecord _ record newFields ->
                    Element.column [ Element.height fill ]
                        [ Element.row [ smallPadding config.state.theme |> padding ] [ text "updating ", viewValue config record, text " with" ]
                        , ViewRecord.view config (viewValue config) newFields
                        ]

                Value.Destructure _ pattern val1 val2 ->
                    ViewDestructure.view config viewValue pattern val1 val2

                Value.LetRecursion tpe definitionDict val ->
                    Element.column [] (Dict.map (\k v -> Value.LetDefinition tpe k v val) definitionDict |> Dict.values |> List.map (viewValue config))

                other   ->
                    let
                        unableToVisualize = 
                            Element.column
                                [ Background.color (rgb 1 0.6 0.6)
                                , smallPadding config.state.theme |> padding
                                , Border.rounded 6
                                ]
                                [ Element.el
                                    [ smallPadding config.state.theme |> padding
                                    , Font.bold
                                    ]
                                    (Element.text "No visual mapping found for:")
                                , Element.el
                                    [ Background.color (rgb 1 1 1)
                                    , smallPadding config.state.theme |> padding
                                    , Border.rounded 6
                                    , width fill
                                    ]
                                    (XRayView.viewValue (XRayView.viewType moduleNameToPathString) ((other |> Debug.log "unable to visualize: ") |> Value.mapValueAttributes identity (\( _, tpe ) -> tpe)))
                                ]
                        in
                    case Config.evaluate (other |> Value.toRawValue) config of
                        Ok valueType ->
                                case fromRawValue config.ir valueType of
                                    Ok enrichedValue ->
                                        viewValue config enrichedValue
                                    Err _ ->
                                        unableToVisualize
                        Err _ ->
                            unableToVisualize
    in
    valueElem


moduleNameToPathString : Path -> String
moduleNameToPathString moduleName =
    pathToStringWithSeparator "/" moduleName


pathToStringWithSeparator : String -> Path -> String
pathToStringWithSeparator =
    Path.toString (Morphir.IR.Name.toHumanWords >> String.join " ")


viewPopup : Config msg -> Element msg
viewPopup config =
    config.state.popupVariables.variableValue
        |> Maybe.map
            (\rawValue ->
                let
                    visualTypedVal : Result TypeError EnrichedValue
                    visualTypedVal =
                        fromRawValue config.ir rawValue

                    popUpStyle : Element msg -> Element msg
                    popUpStyle elementMsg =
                        el
                            [ Border.shadow
                                { offset = ( 2, 2 )
                                , size = 2
                                , blur = 2
                                , color = config.state.theme.colors.darkest
                                }
                            , Background.color config.state.theme.colors.lightest
                            , Font.bold
                            , Font.color config.state.theme.colors.darkest
                            , Border.rounded 4
                            , Font.center
                            , mediumPadding config.state.theme |> padding
                            , htmlAttribute (style "position" "absolute")
                            , htmlAttribute (style "transition" "all 0.2s ease-in-out")
                            ]
                            elementMsg
                in
                case visualTypedVal of
                    Ok visualTypedValue ->
                        popUpStyle (viewValue config visualTypedValue)

                    Err error ->
                        popUpStyle (text (Infer.typeErrorToMessage error))
            )
        |> Maybe.withDefault (el [] (text ""))
