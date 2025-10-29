-- {"query": "645.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3096} 
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm,
    dense_rank() over (order by u.creationdate desc, u.id desc) as recency_rank
  from users u
  where u.creationdate >= (select max(creationdate) - interval '3 years' from users)
),
tagged_questions as (
  select
    p.id as question_id,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.favoritecount,
    p.title,
    p.tags,
    string_to_array(substring(p.tags, 2, length(p.tags)-2), '><') as tag_arr
  from posts p
  where p.posttypeid = 1
),
exploded_tags as (
  select
    q.question_id,
    q.owneruserid,
    lower(t) as tagname
  from tagged_questions q
  cross join lateral unnest(q.tag_arr) as t
),
user_primary_tag as (
  select
    et.owneruserid as user_id,
    et.tagname,
    count(*) as q_count,
    row_number() over (partition by et.owneruserid order by count(*) desc, et.tagname) as rn
  from exploded_tags et
  group by et.owneruserid, et.tagname
),
user_top_tag as (
  select user_id, tagname as primary_tag, q_count
  from user_primary_tag
  where rn = 1
),
badge_summary as (
  select
    b.userid,
    count(*) filter (where b.class = 1) as gold_count,
    count(*) filter (where b.class = 2) as silver_count,
    count(*) filter (where b.class = 3) as bronze_count,
    count(*) as total_badges,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
post_activity as (
  select
    p.id,
    p.owneruserid,
    p.score,
    p.viewcount,
    p.commentcount,
    p.favoritecount,
    p.creationdate,
    coalesce(p.answercount, 0) as answercount,
    sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_vote_delta,
    count(v.id) filter (where v.votetypeid in (2,3)) as vote_events,
    count(distinct c.id) as comments_made
  from posts p
  left join votes v on v.postid = p.id and v.creationdate >= p.creationdate
  left join comments c on c.postid = p.id
  where p.posttypeid in (1,2)
  group by p.id, p.owneruserid, p.score, p.viewcount, p.commentcount, p.favoritecount, p.creationdate, p.answercount
),
question_close_events as (
  select
    ph.postid as question_id,
    min(ph.creationdate) as first_close_date,
    max(ph.creationdate) as last_close_date,
    count(*) filter (where ph.posthistorytypeid = 10) as close_events,
    count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
    max(case when ph.posthistorytypeid = 10 then ph.comment end) as last_close_reason_id_raw
  from posthistory ph
  join posts p on p.id = ph.postid and p.posttypeid = 1
  where ph.posthistorytypeid in (10,11)
  group by ph.postid
),
duplicates as (
  select
    pl.postid as dup_question_id,
    pl.relatedpostid as canonical_question_id,
    min(pl.creationdate) as first_dup_link
  from postlinks pl
  where pl.linktypeid = 3
  group by pl.postid, pl.relatedpostid
),
user_engagement as (
  select
    u.id as user_id,
    count(distinct q.id) as questions_count,
    count(distinct a.id) as answers_count,
    sum(coalesce(q.score,0)) as question_score_sum,
    sum(coalesce(a.score,0)) as answer_score_sum,
    sum(coalesce(pa.vote_events,0)) as vote_events_sum,
    sum(coalesce(pa.net_vote_delta,0)) as net_vote_delta_sum,
    sum(coalesce(pa.viewcount,0)) filter (where pa.id = q.id) as question_views_sum,
    max(coalesce(pa.creationdate, u.creationdate)) as last_activity_at
  from users u
  left join posts q on q.owneruserid = u.id and q.posttypeid = 1
  left join posts a on a.owneruserid = u.id and a.posttypeid = 2
  left join post_activity pa on pa.owneruserid = u.id
  group by u.id
),
question_quality as (
  select
    q.question_id,
    q.owneruserid as user_id,
    q.creationdate,
    q.score,
    q.viewcount,
    q.answercount,
    q.favoritecount,
    coalesce(qqe.close_events, 0) as close_events,
    coalesce(qqe.reopen_events, 0) as reopen_events,
    case
      when dq.dup_question_id is not null then 1 else 0
    end as is_marked_duplicate,
    case
      when q.viewcount is not null and q.answercount is not null and q.viewcount > 0
        then round((q.score + q.answercount*2 + coalesce(q.favoritecount,0))::numeric / greatest(q.viewcount, 1), 6)
      else null
    end as engagement_ratio
  from tagged_questions q
  left join question_close_events qqe on qqe.question_id = q.question_id
  left join (
    select distinct dup_question_id
    from duplicates
  ) dq on dq.dup_question_id = q.question_id
),
user_ranked as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.location,
    ru.websiteurl_norm,
    ut.primary_tag,
    bs.gold_count,
    bs.silver_count,
    bs.bronze_count,
    bs.total_badges,
    ue.questions_count,
    ue.answers_count,
    ue.question_score_sum,
    ue.answer_score_sum,
    ue.vote_events_sum,
    ue.net_vote_delta_sum,
    ue.question_views_sum,
    ue.last_activity_at,
    count(qq.question_id) as recent_questions,
    avg(qq.engagement_ratio) as avg_engagement_ratio,
    sum(qq.is_marked_duplicate) as dup_questions,
    sum(qq.close_events) as close_events_sum,
    sum(qq.reopen_events) as reopen_events_sum,
    dense_rank() over (
      order by coalesce(ue.answer_score_sum,0) + coalesce(ue.question_score_sum,0) desc,
               coalesce(bs.total_badges,0) desc,
               ru.reputation desc
    ) as global_contrib_rank
  from recent_users ru
  left join user_top_tag ut on ut.user_id = ru.user_id
  left join badge_summary bs on bs.userid = ru.user_id
  left join user_engagement ue on ue.user_id = ru.user_id
  left join question_quality qq on qq.user_id = ru.user_id
  where ru.recency_rank <= 5000
  group by
    ru.user_id, ru.displayname, ru.reputation, ru.location, ru.websiteurl_norm,
    ut.primary_tag, bs.gold_count, bs.silver_count, bs.bronze_count, bs.total_badges,
    ue.questions_count, ue.answers_count, ue.question_score_sum, ue.answer_score_sum,
    ue.vote_events_sum, ue.net_vote_delta_sum, ue.question_views_sum, ue.last_activity_at
),
top_users as (
  select *
  from user_ranked
  where global_contrib_rank <= 1000
),
question_metrics as (
  select
    q.question_id,
    q.user_id,
    q.score,
    q.viewcount,
    q.answercount,
    q.favoritecount,
    q.engagement_ratio,
    row_number() over (partition by q.user_id order by q.score desc nulls last, q.viewcount desc nulls last, q.question_id desc) as rn_best,
    row_number() over (partition by q.user_id order by q.creationdate desc, q.question_id desc) as rn_recent
  from question_quality q
),
best_and_recent as (
  select
    qm.user_id,
    max(case when rn_best = 1 then qm.question_id end) as best_question_id,
    max(case when rn_best = 1 then qm.score end) as best_question_score,
    max(case when rn_best = 1 then qm.viewcount end) as best_question_views,
    max(case when rn_best = 1 then qm.engagement_ratio end) as best_question_engagement,
    max(case when rn_recent = 1 then qm.question_id end) as recent_question_id,
    max(case when rn_recent = 1 then qm.score end) as recent_question_score,
    max(case when rn_recent = 1 then qm.viewcount end) as recent_question_views,
    max(case when rn_recent = 1 then qm.engagement_ratio end) as recent_question_engagement
  from question_metrics qm
  group by qm.user_id
),
user_comment_sentiment as (
  select
    u.id as user_id,
    avg(length(c.text)) as avg_comment_len,
    min(length(c.text)) as min_comment_len,
    max(length(c.text)) as max_comment_len,
    sum(case when c.text ~* '(thanks|great|awesome|helpful)' then 1 when c.text ~* '(bad|terrible|awful|useless)' then -1 else 0 end) as rough_sentiment_score
  from users u
  left join comments c on c.userid = u.id
  group by u.id
),
normalized as (
  select
    tu.*,
    bas.best_question_id,
    bas.best_question_score,
    bas.best_question_views,
    bas.best_question_engagement,
    bas.recent_question_id,
    bas.recent_question_score,
    bas.recent_question_views,
    bas.recent_question_engagement,
    ucs.avg_comment_len,
    ucs.min_comment_len,
    ucs.max_comment_len,
    ucs.rough_sentiment_score,
    -- compute a composite score with null-safe operations
    (
      coalesce(tu.answer_score_sum,0) * 1.0 +
      coalesce(tu.question_score_sum,0) * 0.7 +
      coalesce(tu.total_badges,0) * 5.0 +
      coalesce(tu.avg_engagement_ratio,0) * 100.0 +
      coalesce(bas.best_question_engagement,0) * 50.0 +
      greatest(0, coalesce(ucs.rough_sentiment_score,0)) * 2.0 -
      greatest(0, -coalesce(ucs.rough_sentiment_score,0)) * 1.0
    ) as composite_score
  from top_users tu
  left join best_and_recent bas on bas.user_id = tu.user_id
  left join user_comment_sentiment ucs on ucs.user_id = tu.user_id
),
bucketed as (
  select
    n.*,
    ntile(10) over (order by composite_score desc nulls last) as decile,
    case
      when coalesce(primary_tag, '') = '' then 'no-tag'
      when primary_tag ~ '^[a-z0-9\-\+\#\.]+$' then primary_tag
      else 'other'
    end as primary_tag_norm
  from normalized n
),
tag_baselines as (
  select
    primary_tag_norm,
    avg(composite_score) as tag_avg_score,
    stddev_pop(composite_score) as tag_stddev_score,
    count(*) as tag_user_count
  from bucketed
  group by primary_tag_norm
)
select
  b.user_id,
  b.displayname,
  b.location,
  b.websiteurl_norm as website_url,
  b.reputation,
  b.primary_tag_norm as primary_tag,
  b.gold_count,
  b.silver_count,
  b.bronze_count,
  b.total_badges,
  b.questions_count,
  b.answers_count,
  b.question_score_sum,
  b.answer_score_sum,
  b.vote_events_sum,
  b.net_vote_delta_sum,
  b.question_views_sum,
  b.recent_questions,
  b.dup_questions,
  b.close_events_sum,
  b.reopen_events_sum,
  b.avg_engagement_ratio,
  b.best_question_id,
  b.best_question_score,
  b.best_question_views,
  b.best_question_engagement,
  b.recent_question_id,
  b.recent_question_score,
  b.recent_question_views,
  b.recent_question_engagement,
  b.avg_comment_len,
  b.min_comment_len,
  b.max_comment_len,
  b.rough_sentiment_score,
  b.global_contrib_rank,
  b.decile as performance_decile,
  round(b.composite_score::numeric, 4) as composite_score,
  round((b.composite_score - tb.tag_avg_score)::numeric, 4) as score_vs_tag_avg,
  case
    when tb.tag_stddev_score is null or tb.tag_stddev_score = 0 then null
    else round(((b.composite_score - tb.tag_avg_score) / tb.tag_stddev_score)::numeric, 4)
  end as zscore_within_tag,
  b.last_activity_at
from bucketed b
left join tag_baselines tb on tb.primary_tag_norm = b.primary_tag_norm
where
  -- diverse predicates for benchmarking
  (b.questions_count + b.answers_count) >= 3
  and coalesce(b.avg_engagement_ratio, 0) >= 0
  and (
    b.websiteurl_norm ilike '%http%' or
    (b.location is not null and b.location not ilike '%nowhere%') or
    b.total_badges >= 1
  )
  and (
    b.best_question_id is not null
    or b.recent_question_id is not null
  )
order by
  b.decile asc,
  b.composite_score desc,
  b.global_contrib_rank asc,
  b.user_id asc
limit 500;