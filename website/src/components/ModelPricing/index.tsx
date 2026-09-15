import {useState, type ReactNode} from 'react';
import {
  builtinPrices, isModelPrice, pricingSource, pricingVerifiedAt, validPriceModel,
  type ModelPrice, type PricingConfig,
} from '../../../../contract/pricing';
import styles from './styles.module.css';

const fields = [['input', '输入'], ['cached_input', '缓存输入'], ['output', '输出']] as const;

export default function ModelPricing({pricing, onChange}: {
  pricing?: PricingConfig;
  onChange: (pricing: PricingConfig) => void;
}): ReactNode {
  const [newModel, setNewModel] = useState('');
  const [newPrice, setNewPrice] = useState({input: '', cached_input: '', output: ''});
  const [error, setError] = useState('');
  const overrides = pricing?.models ?? {};
  const models = [...new Set([...Object.keys(builtinPrices), ...Object.keys(overrides)])];
  const setPrice = (model: string, price: ModelPrice) => onChange({models: {...overrides, [model]: price}});
  const resetPrice = (model: string) => {
    const next = {...overrides};
    delete next[model];
    onChange({models: next});
  };
  const addPrice = () => {
    const model = newModel.trim().toLowerCase();
    const price = {input: Number(newPrice.input), cached_input: Number(newPrice.cached_input), output: Number(newPrice.output)};
    if (!validPriceModel(model)) {
      setError('请输入模型 ID，只能包含字母、数字、点、下划线、冒号、斜线和连字符。');
      return;
    }
    if (Object.values(newPrice).some((value) => value.trim() === '') || !isModelPrice(price)) {
      setError('请填写三项单价，范围为 0–1,000,000。');
      return;
    }
    if (!Object.hasOwn(overrides, model) && Object.keys(overrides).length >= 64) {
      setError('最多可保存 64 个模型的自定义价格。');
      return;
    }
    setPrice(model, price);
    setNewModel('');
    setNewPrice({input: '', cached_input: '', output: ''});
    setError('');
  };

  return (
    <div className={styles.editor}>
      <p className={styles.description}>
        单位为 <strong>USD / 百万 Token</strong>。内置价格采用标准短上下文 API 单价，
        <a href={pricingSource} target="_blank" rel="noreferrer">官方价格</a>核对于 {pricingVerifiedAt}。
        修改后随配置一起导出。
      </p>
      <p className={styles.description}>
        Cost 按当前模型单价估算整段会话：普通输入 × 输入价 ＋ 缓存输入 × 缓存价 ＋ 输出 × 输出价。
        切换模型会重新估算；未包含长上下文、加速、缓存写入及工具费用，也不代表订阅账单。
      </p>
      <div className={styles.tableScroll}>
        <table className={styles.table}>
          <thead><tr><th>模型</th>{fields.map(([key, label]) => <th key={key}>{label}</th>)}<th>价格来源</th></tr></thead>
          <tbody>
            {models.map((model) => {
              const custom = Object.hasOwn(overrides, model);
              const builtin = Object.hasOwn(builtinPrices, model);
              const price = custom ? overrides[model] : builtinPrices[model];
              return (
                <tr key={model}>
                  <th scope="row"><code>{model}</code></th>
                  {fields.map(([key, label]) => (
                    <td key={key}>
                      <input
                        type="number" min="0" max="1000000" step="any"
                        aria-label={`${model} ${label}单价`}
                        value={price[key]}
                        onChange={(event) => {
                          const value = event.currentTarget.valueAsNumber;
                          if (Number.isFinite(value)) setPrice(model, {...price, [key]: value});
                        }}
                      />
                    </td>
                  ))}
                  <td>
                    {custom ? <button type="button" onClick={() => resetPrice(model)} aria-label={`${model} ${builtin ? '恢复内置价格' : '删除自定义价格'}`}>
                      {builtin ? '恢复内置' : '删除'}
                    </button> : <span className={styles.builtin}>内置</span>}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      <div className={styles.addForm}>
        <label><span>自定义模型 ID</span><input value={newModel} maxLength={128} placeholder="例如 my-model" onChange={(event) => setNewModel(event.target.value)} /></label>
        {fields.map(([key, label]) => (
          <label key={key}><span>{label}单价</span><input type="number" min="0" max="1000000" step="any" value={newPrice[key]}
            onChange={(event) => setNewPrice((current) => ({...current, [key]: event.target.value}))} /></label>
        ))}
        <button type="button" onClick={addPrice}>保存自定义价格</button>
      </div>
      {error ? <p className={styles.error} role="alert">{error}</p> : null}
    </div>
  );
}
