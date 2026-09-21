import {useState, type ReactNode} from 'react';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import {
  builtinPrices, isModelPrice, pricingSource, pricingVerifiedAt, validPriceModel,
  type ModelPrice, type PricingConfig,
} from '../../../../contract/pricing';
import styles from './styles.module.css';

const fields = [['input', 'Input'], ['cached_input', 'Cached input'], ['output', 'Output']] as const;

export default function ModelPricing({pricing, onChange}: {
  pricing?: PricingConfig;
  onChange: (pricing: PricingConfig) => void;
}): ReactNode {
  const {i18n} = useDocusaurusContext();
  const english = i18n.currentLocale === 'en';
  const text = (zh: string, en: string) => english ? en : zh;
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
      setError(text('请输入模型 ID，只能包含字母、数字、点、下划线、冒号、斜线和连字符。', 'Enter a model ID using letters, numbers, dots, underscores, colons, slashes, or hyphens.'));
      return;
    }
    if (Object.values(newPrice).some((value) => value.trim() === '') || !isModelPrice(price)) {
      setError(text('请填写三项单价，范围为 0–1,000,000。', 'Enter all three prices between 0 and 1,000,000.'));
      return;
    }
    if (!Object.hasOwn(overrides, model) && Object.keys(overrides).length >= 64) {
      setError(text('最多可保存 64 个模型的自定义价格。', 'You can save custom prices for at most 64 models.'));
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
        {text('单位为 ', 'Prices are ')}<strong>USD / {text('百万 Token', 'million tokens')}</strong>{text('。内置价格采用标准短上下文 API 单价，', '. Built-in prices use standard short-context API rates, ')}
        <a href={pricingSource} target="_blank" rel="noreferrer">{text('官方价格', 'official pricing')}</a>{text('核对于 ', ' verified on ')}{pricingVerifiedAt}{text('。修改后随配置一起导出。', '. Changes are exported with the configuration.')}
      </p>
      <p className={styles.description}>
        {text('Cost 按各次请求使用的模型分别累计：普通输入 × 输入价 ＋ 缓存输入 × 缓存价 ＋ 输出 × 输出价。此预览使用单一模型的模拟用量，切换模型会更新示例费用。估算未包含长上下文、加速、缓存写入及工具费用，也不代表订阅账单。', 'Cost is accumulated per request model: regular input × input price + cached input × cached price + output × output price. This preview uses one model and sample usage, so switching models changes the example cost. Estimates exclude long-context, acceleration, cache-write, and tool charges and are not subscription bills.')}
      </p>
      <div className={styles.tableScroll}>
        <table className={styles.table}>
          <thead><tr><th>{text('模型', 'Model')}</th>{fields.map(([key, label]) => <th key={key}>{english ? label : ({Input: '输入', 'Cached input': '缓存输入', Output: '输出'} as Record<string, string>)[label]}</th>)}<th>{text('价格来源', 'Price source')}</th></tr></thead>
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
                        aria-label={`${model} ${label} ${text('单价', 'price')}`}
                        value={price[key]}
                        onChange={(event) => {
                          const value = event.currentTarget.valueAsNumber;
                          if (Number.isFinite(value)) setPrice(model, {...price, [key]: value});
                        }}
                      />
                    </td>
                  ))}
                  <td>
                    {custom ? <button type="button" onClick={() => resetPrice(model)} aria-label={`${model} ${text(builtin ? '恢复内置价格' : '删除自定义价格', builtin ? 'restore built-in price' : 'delete custom price')}`}>
                      {builtin ? text('恢复内置', 'Restore built-in') : text('删除', 'Delete')}
                    </button> : <span className={styles.builtin}>{text('内置', 'Built-in')}</span>}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      <div className={styles.addForm}>
        <label><span>{text('自定义模型 ID', 'Custom model ID')}</span><input value={newModel} maxLength={128} placeholder={text('例如 my-model', 'e.g. my-model')} onChange={(event) => setNewModel(event.target.value)} /></label>
        {fields.map(([key, label]) => (
          <label key={key}><span>{english ? label : ({Input: '输入', 'Cached input': '缓存输入', Output: '输出'} as Record<string, string>)[label]}{text('单价', 'price')}</span><input type="number" min="0" max="1000000" step="any" value={newPrice[key]}
            onChange={(event) => setNewPrice((current) => ({...current, [key]: event.target.value}))} /></label>
        ))}
        <button type="button" onClick={addPrice}>{text('保存自定义价格', 'Save custom price')}</button>
      </div>
      {error ? <p className={styles.error} role="alert">{error}</p> : null}
    </div>
  );
}
