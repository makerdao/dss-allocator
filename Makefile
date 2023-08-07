certora-buffer :; PATH=~/.solc-select/artifacts/solc-0.8.16:~/.solc-select/artifacts:${PATH} certoraRun --solc_map AllocatorBuffer=solc-0.8.16,GemMock=solc-0.8.16 --solc_optimize_map AllocatorBuffer=200,GemMock=0 --rule_sanity basic src/AllocatorBuffer.sol test/mocks/GemMock.sol --verify AllocatorBuffer:certora/AllocatorBuffer.spec$(if $(short), --short_output,)$(if $(rule), --rule $(rule),)$(if $(multi), --multi_assert_check,)
certora-vault :; PATH=~/.solc-select/artifacts/solc-0.8.16:~/.solc-select/artifacts:${PATH} certoraRun --solc_map AllocatorVault=solc-0.8.16,AllocatorRoles=solc-0.8.16,VatMock=solc-0.8.16,JugMock=solc-0.8.16,GemJoinMock=solc-0.8.16,GemMock=solc-0.8.16,NstJoinMock=solc-0.8.16,NstMock=solc-0.8.16 --solc_optimize_map AllocatorVault=200,AllocatorRoles=200,VatMock=0,JugMock=0,GemJoinMock=0,NstJoinMock=0,GemMock=0,NstMock=0 --rule_sanity basic src/AllocatorVault.sol src/AllocatorRoles.sol test/mocks/VatMock.sol test/mocks/JugMock.sol test/mocks/GemJoinMock.sol test/mocks/GemMock.sol test/mocks/NstJoinMock.sol test/mocks/NstMock.sol --link AllocatorVault:roles=AllocatorRoles AllocatorVault:vat=VatMock AllocatorVault:jug=JugMock AllocatorVault:gemJoin=GemJoinMock AllocatorVault:nstJoin=NstJoinMock JugMock:vat=VatMock GemJoinMock:vat=VatMock GemJoinMock:gem=GemMock NstJoinMock:vat=VatMock NstJoinMock:nst=NstMock --verify AllocatorVault:certora/AllocatorVault.spec --prover_args '-splitParallel true -depth 15 -dontStopAtFirstSplitTimeout true -numOfParallelSplits 5 -splitParallelTimelimit 7000' --smt_timeout 3600$(if $(short), --short_output,)$(if $(rule), --rule $(rule),)$(if $(multi), --multi_assert_check,)
certora-roles :; PATH=~/.solc-select/artifacts/solc-0.8.16:~/.solc-select/artifacts:${PATH} certoraRun --solc_map AllocatorRoles=solc-0.8.16 --solc_optimize_map AllocatorRoles=200 --rule_sanity basic src/AllocatorRoles.sol --verify AllocatorRoles:certora/AllocatorRoles.spec$(if $(short), --short_output,)$(if $(rule), --rule $(rule),)$(if $(multi), --multi_assert_check,)
certora-oracle :; PATH=~/.solc-select/artifacts/solc-0.8.16:~/.solc-select/artifacts:${PATH} certoraRun --solc_map AllocatorOracle=solc-0.8.16 --solc_optimize_map AllocatorOracle=200 --rule_sanity basic src/AllocatorOracle.sol --verify AllocatorOracle:certora/AllocatorOracle.spec$(if $(short), --short_output,)$(if $(rule), --rule $(rule),)$(if $(multi), --multi_assert_check,)
certora-registry :; PATH=~/.solc-select/artifacts/solc-0.8.16:~/.solc-select/artifacts:${PATH} certoraRun --solc_map AllocatorRegistry=solc-0.8.16 --solc_optimize_map AllocatorRegistry=200 --rule_sanity basic src/AllocatorRegistry.sol --verify AllocatorRegistry:certora/AllocatorRegistry.spec$(if $(short), --short_output,)$(if $(rule), --rule $(rule),)$(if $(multi), --multi_assert_check,)
