library(ggplot2)
library(sqldf)
library(Cairo)
library(patchwork)
library(ggrepel)
options(width = 1000)

features <- read.csv("analysis/features/v1.1/stackoverflow_dba_sqlstorm.csv.gz")
operators <- read.csv("analysis/features/v1.1/stackoverflow_dba_sqlstorm_operators.csv.gz")
models <- read.csv("analysis/llm.csv")
queries <- read.csv("analysis/queries/v1.1/stackoverflow.csv.gz")
price_per_model <- sqldf("
  select prompt, q.model, count(*), round(sum(output_tokens*output + input_tokens*input) / 1000000, 3) as price
  from queries q join models m on q.model = m.model
  group by prompt, q.model
")
print(price_per_model, row.names = FALSE)

d <- sqldf("
with opcount as (
  select query, count(*) as total, sum(case when complexity = 'high' then 1 else 0 end) as high,
         sum(case when complexity = 'medium' then 1 else 0 end) as medium,
         sum(case when complexity = 'low' then 1 else 0 end) as low
  from operators
  where operator <> 'PipelineBreakerScan' and operator <> 'Result' and ((operator <> 'Map' and operator <> 'Select') or complexity <> 'low') and operator <> 'Temp'
  group by query
),
temp as(
  select *
  from features f join queries q on f.query = q.query
        join models m on q.model = m.model
        join opcount o on f.query = o.query)
select prompt, case when model = 'grok-4-fast-non-reasoning' then 'grok-4-fast' else model end as model, vendor,
  count(*) cnt,
  sum(output_tokens) otokens,
  sum(input_tokens) itokens,
  floor(avg(characters)) as length,
  floor(avg(words)) as words,
  floor(avg(ops)) as ops,
  max(ops) as maxops,
  max(characters) as maxlength,
  round((sum(case when complexity = 'high' then 1.0 when complexity = 'medium' then 0.0 else -1.0 end) / count(*))*100) as complexity,
  round(sum(output_tokens*output + input_tokens*input) / 1000000, 3) as query_price,
  min((select price from price_per_model ppm where ppm.prompt = t.prompt and ppm.model = t.model)) / count(*) * 1000 as functional_price,
  avg( high ) as high_ops,
  avg( medium ) as medium_ops,
  avg( low ) as low_ops,
  avg( total ) as total_ops
from temp t
where state = 'success' and prompt = 'p1'
group by prompt, model, vendor
order by prompt, model;
")
print(d, row.names = FALSE)

CairoPDF("analysis/pdf/ops_cnt.pdf", 6.85, 5)
# (price/cnt) * (100/cnt),
ggplot(d, aes(cnt, ops, color = vendor)) +
  geom_point() +
  geom_label_repel(aes(label = model)) +
  # scale_x_log10() +
  facet_grid(prompt ~ .) +
  theme_bw(20)

dev.off()

text_size <- 10
theme_common <- theme_bw(base_size = text_size) +
  theme(
    legend.position = "top",
    legend.direction = "horizontal",
    legend.key.size = unit(8, "pt"),
    legend.margin = margin(t = 0, r = 0, b = 0, l = 0, unit = "pt"),
    legend.box.margin = margin(t = 0, r = 0, b = 0, l = 0, unit = "pt"),
    axis.title = element_text(size = text_size),
    axis.text = element_text(size = text_size - 1),
    legend.text = element_text(size = text_size - 1),
    legend.title = element_text(size = text_size),
    strip.text = element_text(size = text_size),
    legend.justification = c(1, 1), # anchor at top-left of legend
  )

CairoPDF("analysis/pdf/ops_price.pdf", 6.75, 6)
p_ops <- ggplot(d, aes(functional_price, ops, color = vendor)) +
  geom_point() +
  geom_label_repel(aes(label = model), show.legend = FALSE, size = 2) +
  scale_x_log10() +
  labs(x = "Price per 1000 executable queries [USD]", y = "Operators per query [avg]", color = NULL) +
  theme_common +
  guides(color = guide_legend(nrow = 1, byrow = TRUE)) +
  expand_limits(y = 0)


p_length <- ggplot(d, aes(functional_price, length, color = vendor)) +
  geom_point() +
  geom_label_repel(aes(label = model), show.legend = FALSE, size = 2) +
  scale_x_log10() +
  labs(x = "Price per 1000 executable queries [USD]", y = "Query text length [avg, bytes]", color = NULL) +
  theme_common +
  theme(
    # remove x-axis text/ticks/title on the top plot so only bottom plot shows them
    axis.title.x = element_blank(),
    axis.text.x = element_blank(),
    axis.ticks.x = element_blank()
  ) +
  guides(color = guide_legend(nrow = 1, byrow = TRUE)) +
  expand_limits(y = 0)

# stack vertically, collect a single legend on top, equal heights (change heights if desired)
combined <- (p_length / p_ops) + plot_layout(guides = "collect", heights = c(1, 1))
print(combined + plot_annotation(theme = theme(legend.position = "top")))

dev.off()

CairoPDF("analysis/pdf/ops_price2.pdf", 7.5, 4)
ggplot(d, aes(functional_price, ops, color = vendor)) +
  geom_point() +
  geom_label_repel(aes(label = model), show.legend = FALSE, size = 3) +
  scale_x_log10() +
  labs(x = "Price per 1000 executable queries [USD]", y = "Operators per query [avg]", color = NULL) +
  theme_common +
  guides(color = guide_legend(nrow = 1, byrow = TRUE)) +
  expand_limits(y = 0)
dev.off()

CairoPDF("maxops.pdf", 16, 12)
ggplot(d, aes(ops, maxops, color = vendor)) +
  geom_point() +
  geom_label_repel(aes(label = model), show.legend = FALSE) +
  geom_abline(intercept = 0, slope = 1, linetype = "dashed", color = "gray50") +
  geom_abline(intercept = 0, slope = 2, linetype = "dashed", color = "gray50") +
  geom_abline(intercept = 0, slope = 3, linetype = "dashed", color = "gray50") +
  geom_abline(intercept = 0, slope = 4, linetype = "dashed", color = "gray50") +
  labs(color = NULL) +
  theme_bw(20)
dev.off()

CairoPDF("ops_length.pdf", 16, 12)
ggplot(d, aes(length, ops, color = vendor)) +
  geom_point() +
  geom_label_repel(aes(label = model)) +
  facet_grid(prompt ~ .) +
  theme_bw(20)

dev.off()

CairoPDF("length_price.pdf", 16, 12)
ggplot(d, aes(functional_price, length, color = vendor)) +
  geom_point() +
  geom_label_repel(aes(label = model)) +
  scale_x_log10() +
  facet_grid(prompt ~ .) +
  theme_bw(20)

dev.off()

CairoPDF("words_price.pdf", 16, 12)
ggplot(d, aes(functional_price, words, color = vendor)) +
  geom_point() +
  geom_label_repel(aes(label = model)) +
  scale_x_log10() +
  facet_grid(prompt ~ .) +
  theme_bw(20)

dev.off()

d2 <- sqldf("
with temp as(
  select *
  from features f join queries q on f.query = q.query
        join models m on q.model = m.model
)
select *, case when state = 'success' then complexity else 'high' end as result,
case when model = 'grok-4-fast-non-reasoning' then 'grok-4-fast' else model end as m,
round((select price from price_per_model ppm where ppm.prompt = t.prompt and ppm.model = t.model) / (count(*) over (partition by model)) * 1000, 2) as price
from temp t
where prompt = 'p2' and state = 'success'
order by price
")
d2$result <- factor(d2$result, levels = c("low", "medium", "high"))

CairoPDF("analysis/pdf/success_fail.pdf", 3.3, 6)
ggplot(d2, aes(y = reorder(m, -price), fill = result)) +
  geom_bar(position = position_stack(reverse = TRUE)) +
  scale_fill_discrete(
    breaks = c("low", "medium", "high")
  ) +
  labs(x = "Query Count", y = "Model", fill = "Complexity: ") +
  theme_common +
  theme(
    legend.justification = c(1, 1), # anchor at top-left of legend
  )
dev.off()

# aggregate counts per model/result and compute totals per model
counts <- sqldf("
  select m, price, result, count(*) as cnt
  from d2
  group by m, price, result
")
totals <- sqldf("
  select m, price, sum(cnt) as total
  from counts
  group by m, price
")
CairoPDF("analysis/pdf/success_fail_price_p2.pdf", 3.3, 6)
# stacked horizontal bars (use geom_col with x = cnt so stacking is horizontal)
p <- ggplot(counts, aes(x = cnt, y = reorder(m, -price), fill = result)) +
  geom_col(position = position_stack(reverse = TRUE)) +
  scale_fill_discrete(
    breaks = c("low", "medium", "high")
  ) +
  labs(x = "Query Count", y = NULL, fill = "Complexity: ") +
  theme_common +
  theme(
    legend.justification = c(1, 1) # anchor at top-left of legend
  ) +
  # reserve some space on the right so price labels are not clipped
  scale_x_continuous(expand = expansion(mult = c(0, 0.20)))

# add price labels to the right of each stacked bar
p <- p + geom_text(
  data = totals,
  aes(x = total, y = reorder(m, -price), label = sprintf('$ %.2f', price)),
  inherit.aes = FALSE,
  hjust = -0.05,
  size = 2.5
)

print(p)
dev.off()
