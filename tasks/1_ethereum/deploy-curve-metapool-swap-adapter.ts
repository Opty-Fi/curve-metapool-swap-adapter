import { task } from "hardhat/config";
import { TaskArguments } from "hardhat/types";

import { CurveMetapoolSwapAdapter, CurveMetapoolSwapAdapter__factory } from "../../../typechain";

task("deploy-curve-metapool-swap-adapter").setAction(async function (taskArguments: TaskArguments, { ethers }) {
  const curveMetapoolSwapAdapterFactory: CurveMetapoolSwapAdapter__factory = await ethers.getContractFactory(
    "CurveMetapoolSwapAdapter",
  );
  const curveMetapoolSwapAdapter: CurveMetapoolSwapAdapter = <CurveMetapoolSwapAdapter>(
    await curveMetapoolSwapAdapterFactory.deploy()
  );
  await curveMetapoolSwapAdapter.deployed();
  console.log("CurveMetapoolSwapAdapter deployed to: ", curveMetapoolSwapAdapter.address);
});
