-- {"query": "783.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 4304}
with recent_users as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    u.websiteurl,
    u.upvotes,
    u.downvotes,
    u.views,
    row_number() over (order by u.creationdate desc, u.id) as rn
  from users u
  where u.creationdate >= (select date_trunc('year', max(creationdate)) - interval '2 years' from users)
),
user_badge_stats as (
  select
    b.userid,
    count(*) as badge_count,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
question_core as (
  select
    p.id as post_id,
    p.owneruserid as user_id,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.title,
    p.tags,
    p.acceptedanswerid,
    p.closeddate,
    p.communityowneddate,
    p.favoritecount,
    p.commentcount
  from posts p
  where p.posttypeid = 1
),
answer_core as (
  select
    a.id as answer_id,
    a.parentid as question_id,
    a.owneruserid as user_id,
    a.creationdate,
    a.score
  from posts a
  where a.posttypeid = 2
),
answer_rank as (
  select
    ac.answer_id,
    ac.question_id,
    ac.user_id,
    ac.creationdate,
    ac.score,
    row_number() over (partition by ac.question_id order by ac.score desc nulls last, ac.creationdate asc, ac.answer_id) as rn_by_score,
    rank() over (partition by ac.question_id order by ac.creationdate asc, ac.answer_id) as rank_by_time
  from answer_core ac
),
question_activity as (
  select
    q.post_id,
    count(distinct c.id) as comments_count,
    coalesce(sum(case when v.votetypeid = 2 then 1 else 0 end),0) as upvotes,
    coalesce(sum(case when v.votetypeid = 3 then 1 else 0 end),0) as downvotes,
    coalesce(sum(case when v.votetypeid = 5 then 1 else 0 end),0) as favorites,
    max(case when ph.posthistorytypeid in (4,5,6) then ph.creationdate end) as last_edit_at,
    bool_or(ph.posthistorytypeid in (10,35)) as ever_closed_or_migrated
  from question_core q
  left join comments c on c.postid = q.post_id
  left join votes v on v.postid = q.post_id
  left join posthistory ph on ph.postid = q.post_id
  group by q.post_id
),
dup_links as (
  select
    pl.postid as dup_post_id,
    pl.relatedpostid as original_post_id,
    min(pl.creationdate) as first_dup_link_date
  from postlinks pl
  where pl.linktypeid = 3
  group by pl.postid, pl.relatedpostid
),
question_tags as (
  select
    q.post_id,
    unnest(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><')) as tagname
  from question_core q
  where q.tags is not null and q.tags like '<%>'
),
tag_stats as (
  select
    qt.tagname,
    count(distinct qt.post_id) as tag_question_count,
    sum(q.score) as tag_total_score,
    avg(nullif(q.viewcount,0)) as tag_avg_views
  from question_tags qt
  join question_core q on q.post_id = qt.post_id
  group by qt.tagname
),
user_question_agg as (
  select
    q.user_id,
    count(*) as total_questions,
    sum(case when q.score > 0 then 1 else 0 end) as pos_scored_q,
    sum(coalesce(q.viewcount,0)) as total_views_q,
    avg(q.score) as avg_q_score,
    min(q.creationdate) as first_q_date,
    max(q.creationdate) as last_q_date
  from question_core q
  group by q.user_id
),
user_answer_agg as (
  select
    a.user_id,
    count(*) as total_answers,
    sum(case when a.score > 0 then 1 else 0 end) as pos_scored_a,
    avg(a.score) as avg_a_score,
    min(a.creationdate) as first_a_date,
    max(a.creationdate) as last_a_date
  from answer_core a
  group by a.user_id
),
accepted_answerers as (
  select distinct
    q.post_id,
    q.acceptedanswerid as accepted_answer_id,
    aa.user_id as accepted_user_id
  from question_core q
  left join answer_core aa on aa.answer_id = q.acceptedanswerid
),
first_answerers as (
  select
    ar.question_id,
    ar.answer_id,
    ar.user_id as first_answer_user_id
  from answer_rank ar
  where ar.rank_by_time = 1
),
top_scored_answers as (
  select
    ar.question_id,
    ar.answer_id as top_answer_id,
    ar.user_id as top_answer_user_id
  from answer_rank ar
  where ar.rn_by_score = 1
),
q_enriched as (
  select
    q.post_id,
    q.user_id,
    q.creationdate,
    q.score,
    q.viewcount,
    q.answercount,
    q.title,
    q.tags,
    coalesce(q.favoritecount,0) as favoritecount,
    qa.comments_count,
    qa.upvotes,
    qa.downvotes,
    qa.favorites as vote_favorites,
    qa.last_edit_at,
    qa.ever_closed_or_migrated,
    case when q.closeddate is not null then 1 else 0 end as is_closed,
    case when q.communityowneddate is not null then 1 else 0 end as is_community_owned,
    case when q.acceptedanswerid is not null then 1 else 0 end as has_accepted_answer,
    al.original_post_id,
    al.first_dup_link_date
  from question_core q
  left join question_activity qa on qa.post_id = q.post_id
  left join dup_links al on al.dup_post_id = q.post_id
),
user_rollup as (
  select
    coalesce(uq.user_id, ua.user_id) as user_id,
    coalesce(uq.total_questions, 0) as total_questions,
    coalesce(ua.total_answers, 0) as total_answers,
    coalesce(uq.avg_q_score, 0) as avg_q_score,
    coalesce(ua.avg_a_score, 0) as avg_a_score,
    coalesce(uq.total_views_q, 0) as total_views_q,
    coalesce(uq.pos_scored_q, 0) as pos_scored_q,
    coalesce(ua.pos_scored_a, 0) as pos_scored_a,
    least(coalesce(uq.first_q_date, NULL), coalesce(ua.first_a_date, NULL)) as first_post_date,
    greatest(coalesce(uq.last_q_date, NULL), coalesce(ua.last_a_date, NULL)) as last_post_date
  from user_question_agg uq
  full outer join user_answer_agg ua on ua.user_id = uq.user_id
),
user_quality_bucket as (
  select
    ur.user_id,
    case
      when coalesce(ur.avg_q_score,0) + coalesce(ur.avg_a_score,0) >= 10 and coalesce(ur.total_questions,0) + coalesce(ur.total_answers,0) >= 20 then 'A'
      when coalesce(ur.avg_q_score,0) + coalesce(ur.avg_a_score,0) >= 5 then 'B'
      when coalesce(ur.avg_q_score,0) + coalesce(ur.avg_a_score,0) >= 1 then 'C'
      else 'D'
    end as quality_band
  from user_rollup ur
),
q_tag_mix as (
  select
    qe.post_id,
    count(*) as tag_count,
    sum(case when ts.tag_question_count > 1000 then 1 else 0 end) as popular_tags,
    sum(case when ts.tag_question_count <= 100 then 1 else 0 end) as niche_tags,
    max(ts.tag_total_score) as max_tag_total_score,
    avg(ts.tag_avg_views) as avg_tag_avg_views
  from q_enriched qe
  left join question_tags qt on qt.post_id = qe.post_id
  left join tag_stats ts on ts.tagname = qt.tagname
  group by qe.post_id
),
q_scoring as (
  select
    qe.post_id,
    qe.user_id,
    qe.creationdate,
    qe.score,
    qe.viewcount,
    qe.answercount,
    qe.title,
    qc.tag_count,
    qc.popular_tags,
    qc.niche_tags,
    qc.max_tag_total_score,
    qc.avg_tag_avg_views,
    qe.favoritecount + qe.vote_favorites as total_favorites,
    least(coalesce(qe.upvotes - qe.downvotes, 0), 1000) as net_votes_capped,
    case when qe.ever_closed_or_migrated or qe.is_closed = 1 then 1 else 0 end as is_or_was_closed,
    case when qe.has_accepted_answer = 1 then 1 else 0 end as has_accepted_answer,
    extract(epoch from (timestamp '2024-10-01 12:34:56' - qe.creationdate)) / 86400.0 as age_days,
    case when qe.viewcount is null or qe.viewcount = 0 then null else cast(qe.score as numeric) / qe.viewcount end as score_per_view
  from q_enriched qe
  join q_tag_mix qc on qc.post_id = qe.post_id
),
user_dim as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate as user_created,
    u.location,
    nullif(trim(coalesce(u.websiteurl,'')), '') as websiteurl,
    u.upvotes,
    u.downvotes,
    u.views as profile_views
  from users u
),
user_final as (
  select
    ud.*,
    coalesce(ub.badge_count,0) as badge_count,
    coalesce(ub.gold_badges,0) as gold_badges,
    coalesce(ub.silver_badges,0) as silver_badges,
    coalesce(ub.bronze_badges,0) as bronze_badges,
    ur.total_questions,
    ur.total_answers,
    ur.avg_q_score,
    ur.avg_a_score,
    ur.total_views_q,
    ur.pos_scored_q,
    ur.pos_scored_a,
    ur.first_post_date,
    ur.last_post_date,
    uqb.quality_band
  from user_dim ud
  left join user_badge_stats ub on ub.userid = ud.user_id
  left join user_rollup ur on ur.user_id = ud.user_id
  left join user_quality_bucket uqb on uqb.user_id = ud.user_id
),
question_league as (
  select
    qs.post_id,
    qs.user_id,
    qs.title,
    qs.creationdate,
    dense_rank() over (order by (qs.net_votes_capped + coalesce(qs.total_favorites,0)) desc, qs.viewcount desc nulls last) as popularity_rank,
    ntile(10) over (order by coalesce(qs.viewcount,0) desc) as views_decile,
    ntile(10) over (order by coalesce(qs.score,0) desc) as score_decile
  from q_scoring qs
),
answer_outcomes as (
  select
    q.post_id,
    case when aa.accepted_answer_id is not null then 1 else 0 end as has_accepted,
    case when aa.accepted_user_id = fa.first_answer_user_id and aa.accepted_answer_id is not null then 1 else 0 end as accepted_first_answerer,
    case when aa.accepted_user_id = tsa.top_answer_user_id and aa.accepted_answer_id is not null then 1 else 0 end as accepted_top_scorer
  from q_enriched q
  left join accepted_answerers aa on aa.post_id = q.post_id
  left join first_answerers fa on fa.question_id = q.post_id
  left join top_scored_answers tsa on tsa.question_id = q.post_id
),
recent_dupes as (
  select
    q.post_id,
    count(case when dl.first_dup_link_date >= timestamp '2024-10-01 12:34:56' - interval '365 days' then 1 end) as recent_dup_links
  from q_enriched q
  left join dup_links dl on dl.dup_post_id = q.post_id
  group by q.post_id
),
user_recent_activity as (
  select
    u.id as user_id,
    sum(case when p.posttypeid = 1 and p.creationdate >= timestamp '2024-10-01 12:34:56' - interval '90 days' then 1 else 0 end) as q_90d,
    sum(case when p.posttypeid = 2 and p.creationdate >= timestamp '2024-10-01 12:34:56' - interval '90 days' then 1 else 0 end) as a_90d,
    sum(case when p.posttypeid = 1 and p.creationdate >= timestamp '2024-10-01 12:34:56' - interval '30 days' then 1 else 0 end) as q_30d,
    sum(case when p.posttypeid = 2 and p.creationdate >= timestamp '2024-10-01 12:34:56' - interval '30 days' then 1 else 0 end) as a_30d
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id
),
scored_questions as (
  select
    qs.*,
    ql.popularity_rank,
    ql.views_decile,
    ql.score_decile,
    ao.has_accepted,
    ao.accepted_first_answerer,
    ao.accepted_top_scorer,
    rd.recent_dup_links,
    case
      when qs.is_or_was_closed = 1 then 'closed'
      when qs.has_accepted_answer = 1 then 'solved'
      when coalesce(qs.answercount,0) = 0 and qs.age_days > 365 then 'stale'
      else 'open'
    end as status_bucket
  from q_scoring qs
  left join question_league ql on ql.post_id = qs.post_id
  left join answer_outcomes ao on ao.post_id = qs.post_id
  left join recent_dupes rd on rd.post_id = qs.post_id
),
user_tag_affinity as (
  select
    qe.user_id,
    qt.tagname,
    count(*) as q_count_for_tag,
    avg(qe.score) as avg_score_for_tag
  from q_enriched qe
  join question_tags qt on qt.post_id = qe.post_id
  group by qe.user_id, qt.tagname
),
user_primary_tag as (
  select distinct on (uta.user_id)
    uta.user_id,
    uta.tagname as primary_tag,
    uta.q_count_for_tag,
    uta.avg_score_for_tag
  from user_tag_affinity uta
  order by uta.user_id, uta.q_count_for_tag desc, uta.avg_score_for_tag desc nulls last, uta.tagname
),
stringy as (
  select
    sf.post_id,
    upper(coalesce(sf.title,'')) as title_upper,
    length(coalesce(sf.title,'')) as title_len,
    position('?' in coalesce(sf.title,'')) as qmark_pos,
    regexp_replace(coalesce(sf.title,''), '\s+', ' ', 'g') as title_norm
  from scored_questions sf
),
final_score as (
  select
    sf.post_id,
    sf.user_id,
    sf.title,
    sf.creationdate,
    sf.score,
    sf.viewcount,
    sf.answercount,
    sf.total_favorites,
    sf.net_votes_capped,
    sf.tag_count,
    sf.popular_tags,
    sf.niche_tags,
    sf.status_bucket,
    sf.has_accepted,
    sf.accepted_first_answerer,
    sf.accepted_top_scorer,
    sf.popularity_rank,
    sf.views_decile,
    sf.score_decile,
    sf.age_days,
    coalesce(sa.title_len, 0) as title_len,
    coalesce(sa.qmark_pos, 0) as title_qmark_pos,
    round(
      greatest(0,
        (coalesce(sf.score,0) * 3)
        + (coalesce(sf.viewcount,0) / 100.0)
        + (coalesce(sf.total_favorites,0) * 5)
        + (case when sf.has_accepted = 1 then 50 else 0 end)
        + (case when sf.status_bucket = 'closed' then -40 when sf.status_bucket = 'stale' then -10 else 0 end)
        + (coalesce(sf.popular_tags,0) * 2 - coalesce(sf.niche_tags,0))
        + (least(coalesce(sa.title_len,0), 120) / 4.0)
        - (case when sa.qmark_pos > 0 then 1 else 0 end)
        + (10 - coalesce(sf.views_decile,10))
        + (10 - coalesce(sf.score_decile,10))
      )
    , 2) as benchmark_score
  from scored_questions sf
  left join stringy sa on sa.post_id = sf.post_id
)
select
  fs.post_id,
  fs.user_id,
  u.displayname,
  u.reputation,
  u.quality_band,
  coalesce(upt.primary_tag, '(none)') as primary_tag,
  u.badge_count,
  u.gold_badges,
  u.silver_badges,
  u.bronze_badges,
  ura.q_30d,
  ura.a_30d,
  ura.q_90d,
  ura.a_90d,
  fs.title,
  fs.creationdate,
  fs.score,
  fs.viewcount,
  fs.answercount,
  fs.tag_count,
  fs.popular_tags,
  fs.niche_tags,
  fs.status_bucket,
  fs.has_accepted,
  fs.accepted_first_answerer,
  fs.accepted_top_scorer,
  fs.popularity_rank,
  fs.views_decile,
  fs.score_decile,
  fs.age_days,
  fs.title_len,
  fs.title_qmark_pos,
  fs.benchmark_score,
  rank() over (order by fs.benchmark_score desc, fs.popularity_rank asc, fs.post_id) as global_rank
from final_score fs
join user_final u on u.user_id = fs.user_id
left join user_primary_tag upt on upt.user_id = u.user_id
left join user_recent_activity ura on ura.user_id = u.user_id
where
  (
    (fs.benchmark_score >= 50 and fs.has_accepted = 1)
    or (fs.benchmark_score >= 80)
    or (fs.status_bucket in ('open','solved') and fs.viewcount >= 1000 and coalesce(fs.score,0) >= 5)
  )
  and not (u.displayname is null and u.reputation < 50)
  and (fs.title ~ '(?i)(how|why|what|best|performance)' or fs.title_len > 20)
  and (fs.age_days is null or fs.age_days >= 1)
order by fs.benchmark_score desc, fs.popularity_rank asc, fs.post_id
limit 500;