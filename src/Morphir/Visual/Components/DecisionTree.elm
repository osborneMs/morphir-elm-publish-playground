module Morphir.Visual.Components.DecisionTree exposing (BranchNode, LeftOrRight(..), Node(..), downArrow, downArrowHead, highlightColor, horizontalLayout, layout, noPadding, rightArrow, rightArrowHead, verticalLayout)

import Element exposing (Attribute, Color, Element, alignLeft, alignTop, centerX, centerY, column, el, fill, height, html, padding, paddingEach, paddingXY, rgb255, row, shrink, spacing, text, width)
import Element.Border as Border
import Element.Font as Font
import Html exposing (Html)
import Html.Attributes
import Morphir.Visual.Common exposing (element)
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.EnrichedValue exposing (EnrichedValue)
import Morphir.Visual.Theme exposing (mediumPadding, mediumSpacing, smallSpacing)
import Svg
import Svg.Attributes
import Morphir.Visual.Config exposing (HighlightState(..))


type Node
    = Branch BranchNode
    | Leaf EnrichedValue


type alias BranchNode =
    { condition : EnrichedValue
    , conditionValue : Maybe Bool
    , thenBranch : Node
    , elseBranch : Node
    }


type LeftOrRight
    = Left
    | Right


highlightColor : { true : Color, false : Color, default : Color }
highlightColor =
    { true = Color 100 180 100
    , false = Color 180 100 100
    , default = Color 120 120 120
    }


type Color
    = Color Int Int Int


type HighlightState
    = Highlighted Bool
    | NotHighlighted


highlightStateToColor : HighlightState -> Color
highlightStateToColor state =
    case state of
        Highlighted bool ->
            if bool then
                highlightColor.true

            else
                highlightColor.false

        NotHighlighted ->
            highlightColor.default


highlightStateToBackground : HighlightState -> String
highlightStateToBackground state =
    case state of
        NotHighlighted ->
            "repeating-linear-gradient( 45deg, #565656, #9a9595 10px, #656565 10px, #797979 20px )"

        _ ->
            "none"


highlightStateToBorderWidth : HighlightState -> Int
highlightStateToBorderWidth state =
    case state of
        Highlighted _ ->
            4

        NotHighlighted ->
            2


highlightStateToFontWeight : HighlightState -> Attribute msg
highlightStateToFontWeight state =
    case state of
        Highlighted _ ->
            Font.bold

        NotHighlighted ->
            Font.regular


toElementColor : Color -> Element.Color
toElementColor (Color r g b) =
    rgb255 r g b


toCssColor : Color -> String
toCssColor (Color r g b) =
    String.concat [ "rgb(", String.fromInt r, ",", String.fromInt g, ",", String.fromInt b, ")" ]


layout : Config msg -> (Config msg -> EnrichedValue -> Element msg) -> Node -> Element msg
layout config viewValue rootNode =
    layoutHelp config NotHighlighted viewValue rootNode


layoutHelp : Config msg -> HighlightState -> ( Config msg -> EnrichedValue -> Element msg) -> Node -> Element msg
layoutHelp config highlightState viewValue rootNode =
    let
        stateConfig = config.state

        depthOf : (BranchNode -> Node) -> Node -> Int
        depthOf f node =
            case node of
                Branch branch ->
                    depthOf f (f branch) + 1

                Leaf _ ->
                    1
    in
    case rootNode of
        Branch branch ->
            let
                conditionState : HighlightState
                conditionState =
                    case branch.conditionValue of
                        Just v ->
                            Highlighted v

                        _ ->
                            NotHighlighted

                thenState : HighlightState
                thenState =
                    case branch.conditionValue of
                        Just v ->
                            if v then
                                Highlighted True

                            else
                                NotHighlighted

                        _ ->
                            NotHighlighted

                elseState : HighlightState
                elseState =
                    case branch.conditionValue of
                        Just v ->
                            if v then
                                NotHighlighted

                            else
                                Highlighted False

                        _ ->
                            NotHighlighted
            in
            -- TODO: choose vertical/horizontal left/right layout based on some heuristics
            horizontalLayout
                config
                (el
                    [ conditionState |> highlightStateToBorderWidth |> Border.width
                    , Border.rounded 6
                    , Border.color (conditionState |> highlightStateToColor |> toElementColor)
                    , mediumPadding config.state.theme |> padding
                    ]
                    (viewValue {config | state = { stateConfig | highlightState = Just <| branchHighlightToConfigHighLight conditionState } } branch.condition)
                )
                (el
                    [ Font.color (thenState |> highlightStateToColor |> toElementColor)
                    , thenState |> highlightStateToFontWeight
                    ]
                    (text "Yes")
                )
                thenState
                (layoutHelp {config | state = { stateConfig | highlightState = Just <| branchHighlightToConfigHighLight thenState } } thenState viewValue branch.thenBranch)
                (el
                    [ Font.color (elseState |> highlightStateToColor |> toElementColor)
                    , elseState |> highlightStateToFontWeight
                    ]
                    (text "No")
                )
                elseState
                (layoutHelp {config | state = { stateConfig | highlightState = Just <| branchHighlightToConfigHighLight elseState } } elseState viewValue branch.elseBranch)

        Leaf value ->
            el
                [ highlightState |> highlightStateToBorderWidth |> Border.width
                , Border.rounded 6
                , Border.color (highlightState |> highlightStateToColor |> toElementColor)
                , mediumPadding config.state.theme |> padding
                ]
                (viewValue {config | state = { stateConfig | highlightState = Just <| branchHighlightToConfigHighLight highlightState } } value)


horizontalLayout : Config msg -> Element msg -> Element msg -> HighlightState -> Element msg -> Element msg -> HighlightState -> Element msg -> Element msg
horizontalLayout config condition branch1Label branch1State branch1 branch2Label branch2State branch2 =
    row
        []
        [ column
            [ alignTop
            ]
            [ row
                [ width fill
                ]
                [ column
                    [ alignTop
                    , width shrink
                    ]
                    [ el [ width shrink ]
                        condition
                    , row
                        [ alignLeft
                        , height fill
                        , width fill
                        , smallSpacing config.state.theme |> spacing
                        ]
                        [ el
                            [ paddingEach { noPadding | left = mediumPadding config.state.theme }
                            , height fill
                            ]
                            (downArrow config branch1State)
                        , el
                            [ centerY
                            , paddingXY 0 (mediumPadding config.state.theme)
                            ]
                            branch1Label
                        ]
                    ]
                , column
                    [ alignTop
                    , width fill
                    ]
                    [ el
                        [ width fill
                        , paddingEach { noPadding | top = mediumPadding config.state.theme }
                        ]
                        (rightArrow config branch2State)
                    , el
                        [ centerX
                        , mediumPadding config.state.theme |> padding
                        ]
                        branch2Label
                    ]
                ]
            , el
                [ paddingEach { noPadding | right = mediumPadding config.state.theme }
                ]
                branch1
            ]
        , el
            [ alignTop
            ]
            branch2
        ]


verticalLayout : Config msg -> Element msg -> Element msg -> HighlightState -> Element msg -> Element msg -> HighlightState -> Element msg -> Element msg
verticalLayout config condition branch1Label branch1State branch1 branch2Label branch2State branch2 =
    column
        []
        [ row []
            [ column
                [ alignTop
                , height fill
                ]
                [ condition
                , row
                    [ alignLeft
                    , height fill
                    , width fill
                    , mediumSpacing config.state.theme |> spacing
                    ]
                    [ el
                        [ paddingEach { noPadding | left = mediumPadding config.state.theme }
                        , height fill
                        ]
                        (downArrow config branch1State)
                    , el
                        [ centerY
                        , paddingXY 0 (mediumPadding config.state.theme)
                        ]
                        branch1Label
                    ]
                ]
            , column [ alignTop ]
                [ el
                    [ width fill
                    , paddingEach { noPadding | top = mediumPadding config.state.theme }
                    ]
                    (rightArrow config branch2State)
                , el [ centerX, paddingXY (mediumPadding config.state.theme) 0 ]
                    branch2Label
                ]
            , el [ alignTop, paddingEach { noPadding | bottom = mediumPadding config.state.theme } ] branch2
            ]
        , branch1
        ]


rightArrow : Config msg -> HighlightState -> Element msg
rightArrow config highlightState =
    el
        [ width fill
        , height fill
        ]
        (html
            (Html.table
                [ Html.Attributes.style "border-collapse" "collapse"
                , Html.Attributes.style "width" "100%"
                ]
                [ Html.tr []
                    [ Html.td
                        [ Html.Attributes.style "border-bottom" (String.concat [ "solid ", highlightState |> highlightStateToBorderWidth |> String.fromInt, "px ", highlightState |> highlightStateToColor |> toCssColor ])
                        , Html.Attributes.style "width" "100%"
                        ]
                        []
                    , Html.td
                        [ Html.Attributes.rowspan 2 ]
                        [ element
                            (el
                                [ centerY ]
                                (html (rightArrowHead config highlightState))
                            )
                        ]
                    ]
                , Html.tr []
                    [ Html.td [] []
                    ]
                ]
            )
        )


downArrow : Config msg -> HighlightState -> Element msg
downArrow config highlightState =
    el
        [ width fill
        , height fill
        ]
        (html
            (Html.table
                [ Html.Attributes.style "border-collapse" "collapse"
                , Html.Attributes.style "height" "100%"
                ]
                [ Html.tr [ Html.Attributes.style "height" "100%" ]
                    [ Html.td [ Html.Attributes.style "border-right" (String.concat [ "solid ", highlightState |> highlightStateToBorderWidth |> String.fromInt, "px ", highlightState |> highlightStateToColor |> toCssColor ]) ] []
                    , Html.td [] []
                    ]
                , Html.tr []
                    [ Html.td
                        [ Html.Attributes.colspan 2 ]
                        [ element
                            (el
                                [ centerX ]
                                (html (downArrowHead config highlightState))
                            )
                        ]
                    ]
                ]
            )
        )


rightArrowHead : Config msg -> HighlightState -> Html msg
rightArrowHead config highlightState =
    Svg.svg
        [ Svg.Attributes.width
            (if highlightState == NotHighlighted then
                String.fromInt (mediumSpacing config.state.theme)

             else
                String.fromInt (mediumSpacing config.state.theme)
            )
        , Svg.Attributes.height
            (if highlightState == NotHighlighted then
                String.fromInt (mediumSpacing config.state.theme)

             else
                String.fromInt (mediumSpacing config.state.theme)
            )
        , Svg.Attributes.viewBox "0 0 200 200"
        ]
        [ Svg.polygon
            [ Svg.Attributes.points "0,0 200,100 0,200"
            , Svg.Attributes.style ("fill:" ++ (highlightState |> highlightStateToColor |> toCssColor))
            ]
            []
        ]


downArrowHead : Config msg -> HighlightState -> Html msg
downArrowHead config highlightState =
    Svg.svg
        [ Svg.Attributes.width
            (if highlightState == NotHighlighted then
                String.fromInt (mediumSpacing config.state.theme)

             else
                String.fromInt (mediumSpacing config.state.theme)
            )
        , Svg.Attributes.height
            (if highlightState == NotHighlighted then
                String.fromInt (mediumSpacing config.state.theme)

             else
                String.fromInt (mediumSpacing config.state.theme)
            )
        , Svg.Attributes.viewBox "0 0 200 200"
        ]
        [ Svg.polygon
            [ Svg.Attributes.points "0,0 100,200 200,0"
            , Svg.Attributes.style ("fill:" ++ (highlightState |> highlightStateToColor |> toCssColor))
            ]
            []
        ]


noPadding : { right : number, left : number, top : number, bottom : number }
noPadding =
    { right = 0
    , left = 0
    , top = 0
    , bottom = 0
    }


branchHighlightToConfigHighLight : HighlightState -> Morphir.Visual.Config.HighlightState
branchHighlightToConfigHighLight branchHL = 
    case branchHL of
        NotHighlighted ->
            Unmatched

        Highlighted _ ->
            Matched