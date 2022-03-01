import hre from "hardhat";
import { Artifact } from "hardhat/types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { CurveMetapoolSwapAdapter } from "../../../typechain/CurveMetapoolSwapAdapter";
import { TestDeFiAdapter } from "../../../typechain/TestDeFiAdapter";
import { LiquidityPool, Signers } from "../types";
import { shouldBehaveLikeCurveMetapoolSwapAdapter } from "./CurveMetapoolSwapAdapter.behavior";
import { default as CurveExports } from "@optyfi/defi-legos/ethereum/curve/contracts";
import { getOverrideOptions } from "../../utils";

const { deployContract } = hre.waffle;

const CurvePools = CurveExports.CurveMetapoolSwap.pools;

describe("Unit tests", function () {
  before(async function () {
    this.signers = {} as Signers;
    const signers: SignerWithAddress[] = await hre.ethers.getSigners();

    this.signers.admin = signers[0];
    this.signers.owner = signers[1];
    this.signers.deployer = signers[2];
    this.signers.alice = signers[3];
    this.signers.operator = await hre.ethers.getSigner("0x6bd60f089B6E8BA75c409a54CDea34AA511277f6");

    // deploy Curve Metapool Swap Adapter
    const curveMetapoolSwapAdapterArtifact: Artifact = await hre.artifacts.readArtifact("CurveMetapoolSwapAdapter");
    this.curveMetapoolSwapAdapter = <CurveMetapoolSwapAdapter>(
      await deployContract(
        this.signers.deployer,
        curveMetapoolSwapAdapterArtifact,
        ["0x99fa011e33a8c6196869dec7bc407e896ba67fe3"],
        getOverrideOptions(),
      )
    );

    // deploy TestDeFiAdapter Contract
    const testDeFiAdapterArtifact: Artifact = await hre.artifacts.readArtifact("TestDeFiAdapter");
    this.testDeFiAdapter = <TestDeFiAdapter>(
      await deployContract(this.signers.deployer, testDeFiAdapterArtifact, [], getOverrideOptions())
    );
  });

  describe("CurveMetapoolSwapAdapter", function () {
    Object.keys(CurvePools).map((token: string) => {
      shouldBehaveLikeCurveMetapoolSwapAdapter(token, (CurvePools as LiquidityPool)[token]);
    });
  });
});
