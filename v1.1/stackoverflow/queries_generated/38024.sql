-- {"query": "38024.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2131} 
with recent_users as (
  select u.id as user_id, u.displayname, u.reputation, u.creationdate
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
hot_questions as (
  select p.id as question_id,
         p.title,
         p.creationdate,
         p.viewcount,
         p.score,
         p.ownseruserid,
         p.tags,
         coalesce(p.answercount, 0) as answercount
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= (select max(creationdate) - interval '365 days' from posts where posttypeid = 1)
),
answers_last_year as (
  select a.id as answer_id,
         a.parentid as question_id,
         a.owneruserid as answer_owner_id,
         a.creationdate,
         a.score
  from posts a
  where a.posttypeid = 2
    and a.creationdate >= (select max(creationdate) - interval '365 days' from posts where posttypeid = 2)
),
tag_expansion as (
  select hq.question_id,
         unnest(string_to_array(substring(hq.tags, 2, length(hq.tags)-2), '><')) as tag
  from hot_questions hq
  where hq.tags is not null and hq.tags <> ''
),
top_tags as (
  select te.tag, count(*) as tag_usage
  from tag_expansion te
  group by te.tag
  having count(*) >= 10
),
question_metrics as (
  select
    hq.question_id,
    hq.title,
    hq.creationdate,
    hq.viewcount,
    hq.score as question_score,
    hq.answercount,
    count(al.answer_id) as answers_in_period,
    avg(al.score) filter (where al.score is not null) as avg_answer_score,
    max(al.score) as max_answer_score,
    count(distinct c.id) as comment_count,
    count(distinct v.id) filter (where v.votetypeid = 2) as upvotes,
    count(distinct v.id) filter (where v.votetypeid = 3) as downvotes
  from hot_questions hq
  left join answers_last_year al on al.question_id = hq.question_id
  left join comments c on c.postid = hq.question_id
  left join votes v on v.postid = hq.question_id
  group by hq.question_id, hq.title, hq.creationdate, hq.viewcount, hq.score, hq.answercount
),
question_owner as (
  select p.id as question_id, u.id as owner_id, u.displayname as owner_name, u.reputation as owner_rep
  from posts p
  join users u on u.id = p.owneruserid
  where p.posttypeid = 1
),
duplicate_links as (
  select pl.postid as dup_question_id,
         pl.relatedpostid as original_question_id,
         pl.creationdate as link_date
  from postlinks pl
  where pl.linktypeid = 3
),
closing_events as (
  select ph.postid as question_id,
         ph.creationdate as closed_at,
         ph.comment as close_reason_id
  from posthistory ph
  where ph.posthistorytypeid = 10
),
reopen_events as (
  select ph.postid as question_id,
         ph.creationdate as reopened_at
  from posthistory ph
  where ph.posthistorytypeid = 11
),
badge_rollups as (
  select b.userid,
         sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
         sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
         sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
         count(*) as total_badges
  from badges b
  group by b.userid
),
question_tag_scores as (
  select te.question_id,
         avg(t.count) as avg_tag_popularity,
         sum(t.count) as sum_tag_popularity,
         count(*) as tag_count
  from tag_expansion te
  join tags t on lower(t.tagname) = lower(te.tag)
  group by te.question_id
),
engagement_windows as (
  select
    qm.question_id,
    sum(case when v.votetypeid = 2 and v.creationdate <= qm.creationdate + interval '7 days' then 1 else 0 end) as upvotes_7d,
    sum(case when v.votetypeid = 3 and v.creationdate <= qm.creationdate + interval '7 days' then 1 else 0 end) as downvotes_7d,
    sum(case when c.id is not null and c.creationdate <= qm.creationdate + interval '7 days' then 1 else 0 end) as comments_7d
  from question_metrics qm
  left join votes v on v.postid = qm.question_id
  left join comments c on c.postid = qm.question_id
  group by qm.question_id
),
quality_score as (
  select
    qm.question_id,
    0.4 * ln(1 + qm.viewcount) +
    0.3 * coalesce(qm.upvotes,0) -
    0.2 * coalesce(qm.downvotes,0) +
    0.5 * coalesce(qm.answers_in_period,0) +
    0.2 * coalesce(qm.avg_answer_score,0) +
    0.1 * coalesce(qts.avg_tag_popularity,0) +
    0.15 * coalesce(ew.upvotes_7d,0) +
    0.05 * coalesce(ew.comments_7d,0) as score
  from question_metrics qm
  left join question_tag_scores qts on qts.question_id = qm.question_id
  left join engagement_windows ew on ew.question_id = qm.question_id
),
closed_dupe_enriched as (
  select
    hq.question_id,
    hq.title,
    hq.creationdate,
    hq.viewcount,
    qm.question_score,
    qm.answers_in_period,
    qm.avg_answer_score,
    qts.avg_tag_popularity,
    qts.sum_tag_popularity,
    qts.tag_count,
    ce.closed_at,
    case when ce.close_reason_id ~ '^[0-9]+$' then cast(ce.close_reason_id as int) end as close_reason_id,
    re.reopened_at,
    dl.original_question_id,
    qo.owner_id,
    qo.owner_name,
    qo.owner_rep
  from hot_questions hq
  join question_metrics qm on qm.question_id = hq.question_id
  left join question_tag_scores qts on qts.question_id = hq.question_id
  left join closing_events ce on ce.question_id = hq.question_id
  left join reopen_events re on re.question_id = hq.question_id
  left join duplicate_links dl on dl.dup_question_id = hq.question_id
  left join question_owner qo on qo.question_id = hq.question_id
),
owner_badges as (
  select cde.question_id,
         coalesce(br.gold_badges,0) as gold_badges,
         coalesce(br.silver_badges,0) as silver_badges,
         coalesce(br.bronze_badges,0) as bronze_badges,
         coalesce(br.total_badges,0) as total_badges
  from closed_dupe_enriched cde
  left join badge_rollups br on br.userid = cde.owner_id
),
final_ranking as (
  select
    cde.question_id,
    cde.title,
    cde.creationdate,
    cde.viewcount,
    cde.question_score,
    cde.answers_in_period,
    cde.avg_answer_score,
    cde.avg_tag_popularity,
    cde.sum_tag_popularity,
    cde.tag_count,
    cde.closed_at,
    cde.close_reason_id,
    cde.reopened_at,
    cde.original_question_id,
    cde.owner_id,
    cde.owner_name,
    cde.owner_rep,
    ob.gold_badges,
    ob.silver_badges,
    ob.bronze_badges,
    ob.total_badges,
    qs.score as quality_score,
    rank() over (order by qs.score desc, cde.viewcount desc, cde.answers_in_period desc) as quality_rank,
    dense_rank() over (order by coalesce(cde.close_reason_id, 0), coalesce(cde.original_question_id, 0)) as moderation_pattern_rank
  from closed_dupe_enriched cde
  left join owner_badges ob on ob.question_id = cde.question_id
  left join quality_score qs on qs.question_id = cde.question_id
)
select
  fr.quality_rank,
  fr.question_id,
  fr.title,
  fr.creationdate,
  fr.viewcount,
  fr.question_score,
  fr.quality_score,
  fr.answers_in_period,
  fr.avg_answer_score,
  fr.avg_tag_popularity,
  fr.sum_tag_popularity,
  fr.tag_count,
  fr.closed_at,
  fr.close_reason_id,
  fr.reopened_at,
  fr.original_question_id,
  fr.owner_id,
  fr.owner_name,
  fr.owner_rep,
  fr.gold_badges,
  fr.silver_badges,
  fr.bronze_badges,
  fr.total_badges,
  tt.tag,
  tt.tag_usage
from final_ranking fr
left join tag_expansion te on te.question_id = fr.question_id
left join top_tags tt on tt.tag = te.tag
where fr.creationdate >= (select max(creationdate) - interval '365 days' from posts where posttypeid = 1)
order by fr.quality_rank asc, coalesce(tt.tag_usage, 0) desc, fr.question_id
limit 500;