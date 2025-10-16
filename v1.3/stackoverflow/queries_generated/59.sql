-- {"query": "59.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2070} 
with
-- Recent active questions with tag arrays and normalized owner info
recent_qs as (
  select
    p.id,
    p.title,
    coalesce(p.tags,'') as raw_tags,
    regexp_split_to_array(substring(coalesce(p.tags,''),2, greatest(char_length(coalesce(p.tags,'')) - 2,0)), '><') as tags,
    p.owneruserid,
    u.reputation as owner_rep,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.favoritecount,
    p.lastactivitydate
  from posts p
  left join users u on u.id = p.owneruserid
  where p.posttypeid = 1
    and p.creationdate >= now() - interval '1 year'
),

-- Top answer per question with some computed text metrics and NULL-aware scoring
top_answers as (
  select distinct on (a.parentid)
    a.parentid as questionid,
    a.id as answerid,
    a.owneruserid as answer_ownerid,
    a.creationdate as answer_creation,
    a.score as answer_score,
    coalesce(length(a.body),0) as body_len,
    coalesce((length(a.body) - length(replace(a.body, '<code>', '')))/length('<code>'),0) as code_snippets_est,
    (coalesce(length(a.body),0) / nullif(greatest(coalesce(a.score,0),1),0))::numeric as len_per_score,
    a.commentcount,
    a.lastactivitydate
  from posts a
  where a.posttypeid = 2
  order by a.parentid, a.score desc nulls last, a.creationdate asc
),

-- Aggregated vote statistics per post with conditional sums and windowed ranks
vote_agg as (
  select
    v.postid,
    count(*) filter (where v.votetypeid = 2) as upvotes,
    count(*) filter (where v.votetypeid = 3) as downvotes,
    count(*) filter (where v.votetypeid = 5) as favorites,
    sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
    count(*) as total_votes,
    max(v.creationdate) as last_vote_date
  from votes v
  group by v.postid
),

-- User badge density & recency: per user compute badge counts and time since last badge
user_badges as (
  select
    b.userid,
    count(*) as badge_count,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    max(b.date) as last_badge_date,
    now() - max(b.date) as time_since_last_badge
  from badges b
  group by b.userid
),

-- Close/ reopen dynamics from posthistory: most recent close reason and reopen flag
close_activity as (
  select ph.postid,
    max(ph.creationdate) filter (where ph.posthistorytypeid in (10)) as last_close_date,
    max(ph.creationdate) filter (where ph.posthistorytypeid in (11)) as last_reopen_date,
    max(case when ph.posthistorytypeid = 10 then ph.comment end) as close_reason_raw,
    bool_or(ph.posthistorytypeid = 10) as ever_closed,
    bool_or(ph.posthistorytypeid = 11) as ever_reopened
  from posthistory ph
  group by ph.postid
),

-- Compute tag popularity over recent questions (last year) including exploded tags
tags_exploded as (
  select
    id as questionid,
    lower(trim(t)) as tag
  from recent_qs rq
  cross join lateral unnest(rq.tags) t
  where coalesce(t,'') <> ''
),

tag_popularity as (
  select
    te.tag,
    count(*) as question_count,
    sum(rq.viewcount) as total_views,
    avg(rq.score) as avg_score,
    percentile_cont(0.5) within group (order by rq.score) as median_score
  from tags_exploded te
  join recent_qs rq on rq.id = te.questionid
  group by te.tag
  having count(*) >= 5
  order by question_count desc
),

-- Historical link graph metrics for questions (inbound/outbound and duplicates)
link_graph as (
  select
    p.id as questionid,
    sum(case when pl.linktypeid = 1 then 1 else 0 end) filter (where pl.postid = p.id) as outbound_links,
    sum(case when pl.linktypeid = 1 then 1 else 0 end) filter (where pl.relatedpostid = p.id) as inbound_links,
    sum(case when pl.linktypeid = 3 then 1 else 0 end) filter (where pl.postid = p.id) as duplicates_marked,
    sum(case when pl.linktypeid = 3 then 1 else 0 end) filter (where pl.relatedpostid = p.id) as marked_as_duplicate_of
  from posts p
  left join postlinks pl on (pl.postid = p.id or pl.relatedpostid = p.id)
  where p.posttypeid = 1
  group by p.id
),

-- Final selection: join many pieces together, compute score ratios, trends, and windowed ranks
ranked_questions as (
  select
    rq.*,
    coalesce(ta.answerid, -1) as top_answer_id,
    coalesce(ta.answer_score,0) as top_answer_score,
    va.upvotes,
    va.downvotes,
    va.favorites,
    va.total_votes,
    coalesce(ub.badge_count,0) as owner_badges,
    coalesce(ca.ever_closed,false) as ever_closed,
    coalesce(ca.last_close_date, null) as last_close_date,
    coalesce(lg.outbound_links,0) as outbound_links,
    coalesce(lg.inbound_links,0) as inbound_links,
    coalesce(tp.question_count,0) as tag_popularity_count,
    -- computed signals
    (coalesce(rq.score,0) + coalesce(va.upvotes,0) - coalesce(va.downvotes,0))::numeric as net_score_signal,
    case when rq.viewcount > 0 then (coalesce(rq.answercount,0)::numeric / rq.viewcount) else 0 end as answers_per_view,
    case when rq.creationdate < now() - interval '30 days' then
      (coalesce(rq.viewcount,0) / greatest(extract(epoch from (now() - rq.creationdate))/86400,1))::numeric
    else
      (coalesce(rq.viewcount,0) / greatest(extract(epoch from (now() - rq.creationdate))/3600,1))::numeric
    end as normalized_traffic,
    -- null-aware tag list string
    case when coalesce(rq.raw_tags,'') = '' then '<no-tags>' else rq.raw_tags end as tag_list_raw
  from recent_qs rq
  left join top_answers ta on ta.questionid = rq.id
  left join vote_agg va on va.postid = rq.id
  left join user_badges ub on ub.userid = rq.owneruserid
  left join close_activity ca on ca.postid = rq.id
  left join link_graph lg on lg.questionid = rq.id
  left join tag_popularity tp on tp.tag = lower(split_part(coalesce(rq.tags,''), '><', 1)) -- approximate representative tag
),

-- Windowed ranking to stress sort and partitioning
final_ranked as (
  select
    rq.*,
    dense_rank() over (order by net_score_signal desc, normalized_traffic desc nulls last) as global_rank,
    row_number() over (partition by coalesce(owneruserid,-1) order by normalized_traffic desc) as owner_trending_rank,
    percentile_cont(0.9) over (partition by null) over() as p90_dummy -- intentional complex window expression to stress engine
  from ranked_questions rq
)

select
  fr.id,
  fr.title,
  fr.tag_list_raw,
  array_to_string(fr.tags, ',') as tag_csv,
  fr.owneruserid,
  fr.owner_rep,
  fr.net_score_signal,
  fr.normalized_traffic,
  fr.top_answer_id,
  fr.top_answer_score,
  fr.upvotes,
  fr.downvotes,
  fr.favorites,
  fr.owner_badges,
  fr.ever_closed,
  fr.last_close_date,
  fr.outbound_links,
  fr.inbound_links,
  fr.tag_popularity_count,
  fr.answers_per_view,
  fr.global_rank,
  fr.owner_trending_rank
from final_ranked fr
where
  -- complex predicate: either highly scored or rapidly trending with tag popularity, but filter out low-signal posts
  (
    fr.net_score_signal >= greatest(5, least(100, floor(fr.owner_rep / nullif(greatest(fr.owner_badges,1),0)))) -- score scaled by rep/badges
    or (fr.normalized_traffic > 50 and fr.tag_popularity_count >= 10)
  )
  and (fr.answercount >= 1 or fr.favoritecount > 0)
  and (fr.ever_closed = false or fr.last_close_date < now() - interval '90 days')
order by fr.global_rank asc, fr.normalized_traffic desc
limit 250;