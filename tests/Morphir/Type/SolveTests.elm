module Morphir.Type.SolveTests exposing (..)

import Dict
import Expect
import Morphir.IR as IR exposing (IR)
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName exposing (fqn)
import Morphir.IR.SDK as SDK
import Morphir.IR.SDK.Basics exposing (boolType, intType)
import Morphir.IR.SDK.String exposing (stringType)
import Morphir.IR.Type as Type
import Morphir.Type.MetaType as MetaType exposing (MetaType(..), Variable, metaAlias, metaFun, metaRecord, variableByIndex)
import Morphir.Type.Solve as Solve exposing (SolutionMap, unifyMetaType)
import Test exposing (Test, describe, test)


substituteVariableTests : Test
substituteVariableTests =
    let
        assert : String -> SolutionMap -> ( Variable, MetaType ) -> SolutionMap -> Test
        assert msg original ( var, replacement ) expected =
            test msg
                (\_ ->
                    original
                        |> Solve.substituteVariable var replacement
                        |> Expect.equal expected
                )
    in
    describe "substituteVariable"
        [ assert "substitute variable"
            (Solve.fromList
                [ ( variableByIndex 0, MetaVar (variableByIndex 1) )
                ]
            )
            ( variableByIndex 1, MetaVar (variableByIndex 2) )
            (Solve.fromList
                [ ( variableByIndex 0, MetaVar (variableByIndex 2) )
                ]
            )
        , assert "substitute extensible record"
            (Solve.fromList
                [ ( variableByIndex 0, metaRecord (Just (variableByIndex 1)) (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ]) )
                ]
            )
            ( variableByIndex 1, metaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) [] (metaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
            (Solve.fromList
                [ ( variableByIndex 0, metaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) [] (metaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
                ]
            )
        , assert "substitute wrapped extensible record"
            (Solve.fromList
                [ ( variableByIndex 0, metaFun (metaRecord (Just (variableByIndex 1)) (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) (MetaVar (variableByIndex 4)) )
                ]
            )
            ( variableByIndex 1, metaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) [] (metaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
            (Solve.fromList
                [ ( variableByIndex 0, metaFun (metaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) [] (metaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ]))) (MetaVar (variableByIndex 4)) )
                ]
            )
        ]


addSolutionTests : Test
addSolutionTests =
    let
        assert : String -> SolutionMap -> ( Variable, MetaType ) -> SolutionMap -> Test
        assert msg original ( var, newSolution ) expected =
            test msg
                (\_ ->
                    original
                        |> Solve.addSolution IR.empty var newSolution
                        |> Expect.equal (Ok expected)
                )
    in
    describe "addSolution"
        [ assert "substitute extensible record"
            (Solve.fromList
                [ ( variableByIndex 0, metaRecord (Just (variableByIndex 1)) (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ]) )
                ]
            )
            ( variableByIndex 1, metaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) [] (metaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
            (Solve.fromList
                [ ( variableByIndex 0, metaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) [] (metaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
                , ( variableByIndex 1, metaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) [] (metaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
                ]
            )
        , assert "substitute extensible record reversed"
            (Solve.fromList
                [ ( variableByIndex 1, metaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) [] (metaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
                ]
            )
            ( variableByIndex 0, metaRecord (Just (variableByIndex 1)) (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ]) )
            (Solve.fromList
                [ ( variableByIndex 0, metaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) [] (metaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
                , ( variableByIndex 1, metaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) [] (metaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
                ]
            )
        , assert "substitute wrapped extensible record reversed"
            (Solve.fromList
                [ ( variableByIndex 1, metaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) [] (metaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
                ]
            )
            ( variableByIndex 0, metaFun (metaRecord (Just (variableByIndex 1)) (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) (MetaVar (variableByIndex 4)) )
            (Solve.fromList
                [ ( variableByIndex 0, metaFun (metaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) [] (metaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ]))) (MetaVar (variableByIndex 4)) )
                , ( variableByIndex 1, metaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) [] (metaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
                ]
            )
        ]


unifyTests : Test
unifyTests =
    let
        assert : String -> MetaType -> MetaType -> SolutionMap -> Test
        assert testName metaType1 metaType2 expectedResult =
            test testName
                (\_ ->
                    unifyMetaType testIR [] metaType1 metaType2
                        |> Expect.equal (Ok expectedResult)
                )
    in
    describe "unifyMetaType"
        [ assert "alias 1"
            (metaRecord (Just (variableByIndex 0))
                (Dict.fromList
                    [ ( [ "foo" ], MetaType.stringType )
                    , ( [ "bar" ], MetaType.boolType )
                    , ( [ "baz" ], MetaType.intType )
                    ]
                )
            )
            (metaAlias (fqn "Test" "Test" "FooBarBazRecord")
                []
                (metaRecord Nothing
                    (Dict.fromList
                        [ ( [ "foo" ], MetaType.stringType )
                        , ( [ "bar" ], MetaType.boolType )
                        , ( [ "baz" ], MetaType.intType )
                        ]
                    )
                )
            )
            (Solve.fromList
                [ ( variableByIndex 0
                  , metaAlias (fqn "Test" "Test" "FooBarBazRecord")
                        []
                        (metaRecord Nothing
                            (Dict.fromList
                                [ ( [ "foo" ], MetaType.stringType )
                                , ( [ "bar" ], MetaType.boolType )
                                , ( [ "baz" ], MetaType.intType )
                                ]
                            )
                        )
                  )
                ]
            )
        , assert "alias 2"
            (metaAlias (fqn "Test" "Test" "FooBarBazRecord")
                []
                (metaRecord Nothing
                    (Dict.fromList
                        [ ( [ "foo" ], MetaType.stringType )
                        , ( [ "bar" ], MetaType.boolType )
                        , ( [ "baz" ], MetaType.intType )
                        ]
                    )
                )
            )
            (metaRecord (Just (variableByIndex 0))
                (Dict.fromList
                    [ ( [ "foo" ], MetaType.stringType )
                    , ( [ "bar" ], MetaType.boolType )
                    , ( [ "baz" ], MetaType.intType )
                    ]
                )
            )
            (Solve.fromList
                [ ( variableByIndex 0
                  , metaAlias (fqn "Test" "Test" "FooBarBazRecord")
                        []
                        (metaRecord Nothing
                            (Dict.fromList
                                [ ( [ "foo" ], MetaType.stringType )
                                , ( [ "bar" ], MetaType.boolType )
                                , ( [ "baz" ], MetaType.intType )
                                ]
                            )
                        )
                  )
                ]
            )
        ]


testIR : IR
testIR =
    Dict.fromList
        [ ( [ [ "morphir" ], [ "s", "d", "k" ] ]
          , SDK.packageSpec
          )
        , ( [ [ "test" ] ]
          , { modules =
                Dict.fromList
                    [ ( [ [ "test" ] ]
                      , { types =
                            Dict.fromList
                                [ ( [ "custom" ]
                                  , Documented ""
                                        (Type.CustomTypeSpecification []
                                            (Dict.fromList
                                                [ ( [ "custom", "zero" ], [] )
                                                ]
                                            )
                                        )
                                  )
                                , ( [ "foo", "bar", "baz", "record" ]
                                  , Documented ""
                                        (Type.TypeAliasSpecification []
                                            (Type.Record ()
                                                [ Type.Field [ "foo" ] (stringType ())
                                                , Type.Field [ "bar" ] (boolType ())
                                                , Type.Field [ "baz" ] (intType ())
                                                ]
                                            )
                                        )
                                  )
                                ]
                        , values =
                            Dict.empty
                        }
                      )
                    ]
            }
          )
        ]
        |> IR.fromPackageSpecifications
