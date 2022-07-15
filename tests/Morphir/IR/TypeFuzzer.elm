module Morphir.IR.TypeFuzzer exposing (referenceFuzzer, typeFuzzer)

import Dict
import Fuzz exposing (Fuzzer)
import Morphir.IR as IR exposing (IR)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Type as Type exposing (Type)


typeFuzzer : IR -> Int -> Fuzzer (Type ())
typeFuzzer ir depth =
    referenceFuzzer ir depth


referenceFuzzer : IR -> Int -> Fuzzer (Type ())
referenceFuzzer ir depth =
    let
        typeArgs : Type.Specification () -> List Name
        typeArgs typeSpec =
            case typeSpec of
                Type.TypeAliasSpecification args _ ->
                    args

                Type.OpaqueTypeSpecification args ->
                    args

                Type.CustomTypeSpecification args _ ->
                    args

        fuzzerForType : ( FQName, Type.Specification () ) -> Fuzzer (Type ())
        fuzzerForType ( fQName, typeSpec ) =
            typeSpec
                |> typeArgs
                |> List.foldr
                    (\_ fuzzerSoFar ->
                        Fuzz.map2
                            (\argsSoFar argValue ->
                                argValue :: argsSoFar
                            )
                            fuzzerSoFar
                            (typeFuzzer ir (depth - 1))
                    )
                    (Fuzz.constant [])
                |> Fuzz.map (Type.Reference () fQName)
    in
    Fuzz.oneOf
        (ir
            |> IR.typeSpecifications
            |> Dict.toList
            |> List.map fuzzerForType
        )
