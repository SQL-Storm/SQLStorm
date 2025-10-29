-- {"query": "440.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3253}
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'unknown') as website_host,
    row_number() over (partition by coalesce(u.location, 'unknown') order by u.reputation desc, u.id) as rn_by_loc
  from users u
  where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '12 months' from users)
),
user_badge_agg as (
  select
    b.userid,
    count(*) as total_badges,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
post_core as (
  select
    p.id,
    p.posttypeid,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.commentcount,
    p.favoritecount,
    p.closeddate,
    p.acceptedanswerid,
    p.parentid,
    p.title,
    p.tags,
    coalesce(p.lastactivitydate, p.creationdate) as activitydate
  from posts p
  where p.posttypeid in (1,2)
),
q_with_tag as (
  select
    q.id as question_id,
    q.owneruserid as question_owner_id,
    q.creationdate as question_created,
    q.closeddate,
    q.score as q_score,
    q.viewcount as q_views,
    q.answercount,
    q.title,
    q.tags,
    (select count(*) from comments c where c.postid = q.id) as q_comment_count,
    (select sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) from votes v where v.postid = q.id) as q_net_votes,
    array_length(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><'), 1) as tag_count
  from post_core q
  where q.posttypeid = 1
),
answers as (
  select
    a.id as answer_id,
    a.parentid as question_id,
    a.owneruserid as answer_owner_id,
    a.creationdate as answer_created,
    a.score as a_score,
    (select sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) from votes v where v.postid = a.id) as a_net_votes,
    row_number() over (partition by a.parentid order by a.score desc nulls last, a.id) as rn_by_q_score,
    rank() over (partition by a.parentid order by a.creationdate asc) as first_answer_rank
  from post_core a
  where a.posttypeid = 2
),
dupe_links as (
  select
    pl.postid as dup_post_id,
    pl.relatedpostid as target_post_id,
    pl.creationdate as dup_link_date
  from postlinks pl
  where pl.linktypeid = 3
),
history_flags as (
  select
    ph.postid,
    max(case when ph.posthistorytypeid in (10,35) then 1 else 0 end) as was_closed_or_migrated,
    max(case when ph.posthistorytypeid in (11) then 1 else 0 end) as was_reopened,
    max(case when ph.posthistorytypeid in (50) then 1 else 0 end) as was_community_bump,
    min(case when ph.posthistorytypeid in (10,35) then ph.creationdate end) as first_close_migrate_date
  from posthistory ph
  group by ph.postid
),
q_activity as (
  select
    q.question_id,
    q.question_owner_id,
    q.question_created,
    q.closeddate,
    q.q_score,
    q.q_views,
    q.answercount,
    q.title,
    q.tags,
    q.q_comment_count,
    q.q_net_votes,
    q.tag_count,
    hf.was_closed_or_migrated,
    hf.was_reopened,
    hf.was_community_bump,
    hf.first_close_migrate_date,
    dl.target_post_id as marked_duplicate_of
  from q_with_tag q
  left join history_flags hf on hf.postid = q.question_id
  left join dupe_links dl on dl.dup_post_id = q.question_id
),
answer_stats as (
  select
    a.question_id,
    count(*) as total_answers,
    sum(case when a.first_answer_rank = 1 then 1 else 0 end) as has_first_answer,
    max(case when a.rn_by_q_score = 1 then a.a_score end) as top_answer_score,
    max(case when a.rn_by_q_score = 1 then a.answer_id end) as top_answer_id,
    avg(cast(a.a_score as numeric)) as avg_answer_score,
    sum(case when a.a_net_votes > 0 then 1 else 0 end) as pos_net_vote_answers
  from answers a
  group by a.question_id
),
owner_stats as (
  select
    u.id as owner_id,
    count(case when p.posttypeid = 1 then 1 end) as q_count,
    count(case when p.posttypeid = 2 then 1 end) as a_count,
    avg(case when p.posttypeid = 1 then cast(p.score as numeric) end) as avg_q_score,
    avg(case when p.posttypeid = 2 then cast(p.score as numeric) end) as avg_a_score,
    sum(case when p.posttypeid = 1 and p.acceptedanswerid is not null then 1 else 0 end) as q_with_accepted,
    min(p.creationdate) as first_post_date,
    max(p.creationdate) as last_post_date
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id
),
q_tag_expanded as (
  select
    qa.*,
    unnest(coalesce(string_to_array(substring(qa.tags, 2, greatest(length(qa.tags)-2,0)), '><'), array[]::text[]::text[])) as tagname
  from q_activity qa
),
tag_enriched as (
  select
    qte.question_id,
    qte.tagname,
    t.count as tag_global_count,
    t.ismoderatoronly,
    t.isrequired
  from q_tag_expanded qte
  left join tags t on lower(t.tagname) = lower(qte.tagname)
),
q_tag_stats as (
  select
    question_id,
    count(*) as tag_used_count,
    sum(tag_global_count) as sum_tag_popularity,
    sum(case when ismoderatoronly then 1 else 0 end) as mod_only_tags,
    sum(case when isrequired then 1 else 0 end) as req_tags
  from tag_enriched
  group by question_id
),
q_vote_bursts as (
  select
    v.postid as question_id,
    date_trunc('day', v.creationdate) as vote_day,
    sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes_day,
    count(*) filter (where v.votetypeid in (2,3)) as votes_day
  from votes v
  join posts p on p.id = v.postid and p.posttypeid = 1
  group by v.postid, date_trunc('day', v.creationdate)
),
q_vote_burst_stats as (
  select
    qvb.question_id,
    max(qvb.votes_day) as max_votes_in_a_day,
    max(abs(qvb.net_votes_day)) as max_abs_net_votes_in_a_day
  from q_vote_bursts qvb
  group by qvb.question_id
),
q_commenters as (
  select
    c.postid as question_id,
    count(distinct c.userid) as distinct_commenters,
    count(*) as total_comments
  from comments c
  join posts p on p.id = c.postid and p.posttypeid = 1
  group by c.postid
),
cte_sample_users as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.website_host,
    ru.location,
    ubs.total_badges,
    ubs.gold_badges,
    ubs.silver_badges,
    ubs.bronze_badges
  from recent_users ru
  left join user_badge_agg ubs on ubs.userid = ru.user_id
  where ru.rn_by_loc <= 50
),
question_candidates as (
  select
    qa.question_id,
    qa.question_owner_id,
    qa.question_created,
    qa.q_score,
    qa.q_views,
    qa.answercount,
    qa.q_comment_count,
    qa.q_net_votes,
    qa.tag_count,
    qa.was_closed_or_migrated,
    qa.was_reopened,
    qa.was_community_bump,
    qa.first_close_migrate_date,
    qa.marked_duplicate_of
  from q_activity qa
  where qa.question_created >= (select date_trunc('month', max(creationdate)) - interval '6 months' from posts where posttypeid = 1)
),
ranked_questions as (
  select
    qc.question_id,
    qc.question_owner_id,
    qc.question_created,
    qc.q_score,
    qc.q_views,
    qc.answercount,
    qc.q_comment_count,
    qc.q_net_votes,
    qc.tag_count,
    qc.was_closed_or_migrated,
    qc.was_reopened,
    qc.was_community_bump,
    qc.first_close_migrate_date,
    qc.marked_duplicate_of,
    qs.total_answers,
    qs.top_answer_score,
    qs.top_answer_id,
    qs.avg_answer_score,
    qts.tag_used_count,
    qts.sum_tag_popularity,
    qts.mod_only_tags,
    qts.req_tags,
    qvbs.max_votes_in_a_day,
    qvbs.max_abs_net_votes_in_a_day,
    qc.q_views * greatest(1, coalesce(qc.q_score,0) + 1) as view_score_mix,
    row_number() over (
      order by
        coalesce(qc.q_score, 0) desc,
        coalesce(qc.q_views, 0) desc,
        coalesce(qts.sum_tag_popularity, 0) desc,
        qc.question_id
    ) as global_rank
  from question_candidates qc
  left join answer_stats qs on qs.question_id = qc.question_id
  left join q_tag_stats qts on qts.question_id = qc.question_id
  left join q_vote_burst_stats qvbs on qvbs.question_id = qc.question_id
),
owner_join as (
  select
    rq.question_id,
    rq.question_owner_id,
    rq.question_created,
    rq.q_score,
    rq.q_views,
    rq.answercount,
    rq.q_comment_count,
    rq.q_net_votes,
    rq.tag_count,
    rq.was_closed_or_migrated,
    rq.was_reopened,
    rq.was_community_bump,
    rq.first_close_migrate_date,
    rq.marked_duplicate_of,
    rq.total_answers,
    rq.top_answer_score,
    rq.top_answer_id,
    rq.avg_answer_score,
    rq.tag_used_count,
    rq.sum_tag_popularity,
    rq.mod_only_tags,
    rq.req_tags,
    rq.max_votes_in_a_day,
    rq.max_abs_net_votes_in_a_day,
    rq.view_score_mix,
    rq.global_rank,
    os.q_count as owner_q_count,
    os.a_count as owner_a_count,
    os.avg_q_score as owner_avg_q_score,
    os.avg_a_score as owner_avg_a_score
  from ranked_questions rq
  left join owner_stats os on os.owner_id = rq.question_owner_id
),
dupe_target_info as (
  select
    rq.question_id,
    t.title as target_title,
    t.score as target_score,
    t.viewcount as target_views
  from ranked_questions rq
  left join posts t on t.id = rq.marked_duplicate_of
),
normalized as (
  select
    oj.question_id,
    oj.question_owner_id,
    oj.question_created,
    oj.q_score,
    oj.q_views,
    oj.answercount,
    oj.q_comment_count,
    oj.q_net_votes,
    oj.tag_count,
    oj.was_closed_or_migrated,
    oj.was_reopened,
    oj.was_community_bump,
    oj.first_close_migrate_date,
    oj.marked_duplicate_of,
    oj.total_answers,
    oj.top_answer_score,
    oj.top_answer_id,
    oj.avg_answer_score,
    oj.tag_used_count,
    oj.sum_tag_popularity,
    oj.mod_only_tags,
    oj.req_tags,
    oj.max_votes_in_a_day,
    oj.max_abs_net_votes_in_a_day,
    oj.view_score_mix,
    oj.global_rank,
    oj.owner_q_count,
    oj.owner_a_count,
    oj.owner_avg_q_score,
    oj.owner_avg_a_score,
    dti.target_title,
    dti.target_score,
    dti.target_views,
    case when oj.tag_used_count is null or oj.tag_used_count = 0 then 0
         else round(cast(oj.sum_tag_popularity as numeric) / oj.tag_used_count, 2) end as avg_tag_popularity,
    case when oj.total_answers is null or oj.total_answers = 0 then null
         else round(oj.avg_answer_score, 2) end as avg_answer_score_norm,
    case when coalesce(oj.q_views,0) = 0 then 0
         else round(cast(oj.q_score as numeric) / nullif(oj.q_views,0), 6) end as score_per_view
  from owner_join oj
  left join dupe_target_info dti on dti.question_id = oj.question_id
),
final_rank as (
  select
    n.*,
    row_number() over (
      order by
        (coalesce(n.q_score,0) * 3
        + coalesce(n.view_score_mix,0) / 100
        + coalesce(n.max_votes_in_a_day,0)
        + coalesce(n.avg_tag_popularity,0) / 10
        - coalesce(n.mod_only_tags,0) * 2
        - case when n.was_closed_or_migrated = 1 then 50 else 0 end) desc,
        n.question_created desc
    ) as perf_rank
  from normalized n
)
select
  fr.perf_rank,
  fr.global_rank,
  fr.question_id,
  fr.question_owner_id,
  u.displayname as owner_name,
  coalesce(u.location, 'unknown') as owner_location,
  coalesce(u.reputation, 0) as owner_reputation,
  fr.question_created,
  fr.q_score,
  fr.q_views,
  fr.answercount,
  fr.total_answers,
  fr.top_answer_id,
  fr.top_answer_score,
  fr.avg_answer_score_norm,
  fr.q_comment_count,
  fr.q_net_votes,
  fr.tag_count,
  fr.tag_used_count,
  fr.avg_tag_popularity,
  fr.max_votes_in_a_day,
  fr.max_abs_net_votes_in_a_day,
  fr.score_per_view,
  fr.view_score_mix,
  fr.was_closed_or_migrated,
  fr.was_reopened,
  fr.was_community_bump,
  fr.first_close_migrate_date,
  fr.marked_duplicate_of,
  fr.target_title,
  fr.target_score,
  fr.target_views,
  fr.owner_q_count,
  fr.owner_a_count,
  fr.owner_avg_q_score,
  fr.owner_avg_a_score,
  case
    when fr.marked_duplicate_of is not null then 'duplicate'
    when fr.was_closed_or_migrated = 1 and fr.was_reopened = 1 then 'closed-then-reopened'
    when fr.was_closed_or_migrated = 1 then 'closed'
    else 'open'
  end as status_label
from final_rank fr
left join users u on u.id = fr.question_owner_id
where
  (
    fr.q_score >= 5
    or (fr.q_views >= 1000 and coalesce(fr.score_per_view,0) > 0.001)
    or (fr.max_votes_in_a_day is not null and fr.max_votes_in_a_day >= 5)
  )
  and coalesce(u.displayname, '') not ilike '%bot%'
  and not exists (
    select 1
    from cte_sample_users su
    where su.user_id = fr.question_owner_id
      and coalesce(su.total_badges, 0) = 0
  )
order by fr.perf_rank, fr.question_id
limit 500;