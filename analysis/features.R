library(ggplot2)
library(sqldf)
library(Cairo)
library(ggrepel)

features = read.csv('analysis/features/v1.1/stackoverflow_dba_sqlstorm.csv.gz')
models = read.csv('analysis/llm.csv')
queries = read.csv('analysis/queries/v1.1/stackoverflow.csv.gz')

d=sqldf("
with temp as(
  select *
  from features f join queries q on f.query = q.query
        join models m on q.model = m.model)
select prompt, model, vendor,
  count(*) cnt,
  sum(output_tokens), 
  sum(input_tokens),  
  floor(avg(characters)) as length,
  floor(avg(ops)) as ops, 
  round((sum(case when complexity = 'high' then 1.0 when complexity = 'medium' then 0.0 else -1.0 end) / count(*))*100) as complexity_score,
  round(sum(output_tokens*output + input_tokens*input) / 1000000, 3) as price
from temp
where state = 'success'
group by prompt, model, vendor
order by prompt, model;
")
options(width=1000)
print(d, row.names=FALSE)

CairoPDF('density.pdf', 16, 8)
# (price/cnt) * (100/cnt),
ggplot(d, aes( cnt, ops, color=vendor)) +
    geom_point() +
    geom_label_repel(aes(label=model)) +
    #scale_x_log10() +
    facet_grid(prompt ~ .) +
    theme_bw(20)

dev.off()


