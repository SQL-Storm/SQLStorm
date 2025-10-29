-- {"query": "785.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3383} 
with
recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
    coalesce(u.websiteurl, 'N/A') as websiteurl,
    extract(year from u.creationdate) as create_year,
    row_number() over (partition by coalesce(nullif(trim(u.location), ''), 'Unknown') order by u.reputation desc, u.id) as rn_loc
  from users u
  where u.creationdate >= (select max(p.creationdate) - interval '365 days' from posts p)
),
user_badge_rollup as (
  select
    b.userid,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    count(*) as total_badges,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
question_base as (
  select
    p.id as qid,
    p.owneruserid as q_owner_id,
    p.creationdate as q_creation,
    p.score as q_score,
    p.viewcount,
    p.title,
    p.tags,
    (p.answercount) as answercount_reported,
    coalesce(p.closeddate is not null, false) as is_closed
  from posts p
  where p.posttypeid = 1
),
answer_base as (
  select
    a.id as aid,
    a.parentid as qid,
    a.owneruserid as a_owner_id,
    a.creationdate as a_creation,
    a.score as a_score
  from posts a
  where a.posttypeid = 2
),
answers_per_question as (
  select
    qid,
    count(*) as actual_answer_count,
    avg(a_score) as avg_answer_score,
    max(a_score) as max_answer_score,
    min(a_score) as min_answer_score,
    percentile_cont(0.5) within group (order by a_score) as median_answer_score
  from answer_base
  group by qid
),
accepted_answer as (
  select
    q.id as qid,
    q.acceptedanswerid as accepted_aid
  from posts q
  where q.posttypeid = 1 and q.acceptedanswerid is not null
),
votes_rollup as (
  select
    v.postid,
    count(*) filter (where v.votetypeid = 2) as upvotes,
    count(*) filter (where v.votetypeid = 3) as downvotes,
    count(*) filter (where v.votetypeid = 5) as favorites,
    sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_total,
    max(v.creationdate) filter (where v.votetypeid in (8,9)) as last_bounty_date
  from votes v
  group by v.postid
),
comment_stats as (
  select
    c.postid,
    count(*) as comment_count,
    avg(c.score) as avg_comment_score,
    max(c.creationdate) as last_comment_date
  from comments c
  group by c.postid
),
duplicate_links as (
  select
    pl.postid as dup_qid,
    count(*) filter (where pl.linktypeid = 3) as dup_count,
    count(*) filter (where pl.linktypeid = 1) as linked_count,
    min(pl.creationdate) as first_link_date
  from postlinks pl
  group by pl.postid
),
close_reasons as (
  select
    ph.postid as qid,
    max(ph.creationdate) as last_close_event,
    max(case when ph.posthistorytypeid = 10 then try_cast(ph.comment as int) end) as close_reason_id_raw,
    max(case when ph.posthistorytypeid = 10 then ph.comment end) as close_reason_comment
  from posthistory ph
  where ph.posthistorytypeid in (10,11) -- closed or reopened events
  group by ph.postid
),
close_reason_name as (
  select
    cr.qid,
    crt.name as close_reason_name
  from close_reasons cr
  left join closereasontypes crt
    on try_cast(cr.close_reason_id_raw as smallint) = crt.id
),
tag_explode as (
  select
    q.qid,
    unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tagname
  from question_base q
  where q.tags is not null and length(q.tags) > 2
),
tag_rank as (
  select
    te.qid,
    te.tagname,
    t.count as tag_global_count,
    dense_rank() over (partition by te.qid order by coalesce(t.count,0) desc, te.tagname) as tag_pop_rank
  from tag_explode te
  left join tags t on lower(t.tagname) = lower(te.tagname)
),
top_tags_per_question as (
  select
    qid,
    string_agg(tagname, ',' order by tagname) filter (where tag_pop_rank <= 3) as top3_tags,
    max(tag_global_count) as max_tag_popularity
  from tag_rank
  group by qid
),
owner_activity as (
  select
    p.owneruserid as owner_id,
    count(*) filter (where p.posttypeid = 1) as questions_posted,
    count(*) filter (where p.posttypeid = 2) as answers_posted,
    avg(p.score) as avg_post_score,
    max(p.lastactivitydate) as last_activity
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
question_quality as (
  select
    q.qid,
    q.q_owner_id,
    coalesce(apq.actual_answer_count, 0) as actual_answer_count,
    q.answercount_reported,
    v.upvotes,
    v.downvotes,
    coalesce(v.upvotes,0) - coalesce(v.downvotes,0) as net_votes,
    c.comment_count,
    q.viewcount,
    q.q_score,
    coalesce(apq.avg_answer_score,0) as avg_answer_score,
    coalesce(apq.median_answer_score,0) as median_answer_score,
    coalesce(d.dup_count,0) as dup_count,
    case
      when q.is_closed then 1
      when crn.close_reason_name is not null then 1
      else 0
    end as closed_flag,
    greatest(
      coalesce(q.q_score,0) * 1.0,
      coalesce(v.upvotes,0) * 0.8 + coalesce(v.downvotes,0) * -0.5,
      coalesce(q.viewcount,0) / nullif(coalesce(apq.actual_answer_count,1),0)::numeric
    ) as score_variant,
    case
      when coalesce(apq.actual_answer_count,0) = 0 and coalesce(v.upvotes,0) = 0 and coalesce(v.downvotes,0) = 0 then 'cold'
      when coalesce(v.upvotes,0) >= 10 and coalesce(q.viewcount,0) >= 1000 then 'hot'
      when coalesce(d.dup_count,0) > 0 then 'duplicate'
      when q.is_closed then 'closed'
      else 'normal'
    end as q_bucket
  from question_base q
  left join answers_per_question apq on apq.qid = q.qid
  left join votes_rollup v on v.postid = q.qid
  left join comment_stats c on c.postid = q.qid
  left join duplicate_links d on d.dup_qid = q.qid
  left join close_reason_name crn on crn.qid = q.qid
),
user_roll as (
  select
    u.user_id,
    u.displayname,
    u.location_norm,
    u.reputation,
    u.creationdate,
    u.websiteurl,
    ub.gold_badges,
    ub.silver_badges,
    ub.bronze_badges,
    ub.total_badges,
    ub.last_badge_date,
    oa.questions_posted,
    oa.answers_posted,
    oa.avg_post_score,
    oa.last_activity,
    u.rn_loc
  from recent_users u
  left join user_badge_rollup ub on ub.userid = u.user_id
  left join owner_activity oa on oa.owner_id = u.user_id
),
question_owner_enriched as (
  select
    qq.qid,
    qq.q_owner_id,
    ur.displayname as owner_name,
    ur.location_norm as owner_location,
    ur.reputation as owner_reputation,
    ur.total_badges,
    ur.gold_badges,
    ur.silver_badges,
    ur.bronze_badges,
    ur.questions_posted,
    ur.answers_posted,
    ur.avg_post_score,
    ur.last_activity
  from question_quality qq
  left join user_roll ur on ur.user_id = qq.q_owner_id
),
accepted_vs_scores as (
  select
    qb.qid,
    case when ac.accepted_aid is not null then 1 else 0 end as has_accepted,
    max(case when ab.aid = ac.accepted_aid then ab.a_score end) as accepted_score,
    avg(ab.a_score) as avg_all_answer_score
  from question_base qb
  left join accepted_answer ac on ac.qid = qb.qid
  left join answer_base ab on ab.qid = qb.qid
  group by qb.qid, has_accepted
),
ranked_questions as (
  select
    qe.*,
    qq.q_bucket,
    qq.net_votes,
    qq.score_variant,
    qq.q_score,
    qq.actual_answer_count,
    qq.comment_count,
    qq.viewcount,
    avs.has_accepted,
    avs.accepted_score,
    avs.avg_all_answer_score,
    tt.top3_tags,
    tt.max_tag_popularity,
    row_number() over (
      partition by coalesce(qe.owner_location,'Unknown')
      order by
        coalesce(qq.score_variant,0) desc,
        coalesce(qq.net_votes,0) desc,
        qe.owner_reputation desc nulls last,
        qe.qid
    ) as loc_rank
  from question_owner_enriched qe
  left join question_quality qq on qq.qid = qe.qid
  left join accepted_vs_scores avs on avs.qid = qe.qid
  left join top_tags_per_question tt on tt.qid = qe.qid
),
location_agg as (
  select
    coalesce(owner_location,'Unknown') as location_norm,
    count(*) as q_cnt,
    avg(coalesce(score_variant,0)) as avg_score_variant,
    percentile_cont(0.9) within group (order by coalesce(score_variant,0)) as p90_score_variant,
    sum(case when q_bucket = 'hot' then 1 else 0 end) as hot_cnt,
    sum(case when has_accepted = 1 then 1 else 0 end) as accepted_cnt
  from ranked_questions
  group by coalesce(owner_location,'Unknown')
),
cross_loc_compare as (
  select
    rq.qid,
    rq.owner_name,
    rq.owner_location,
    rq.owner_reputation,
    rq.total_badges,
    rq.gold_badges,
    rq.silver_badges,
    rq.bronze_badges,
    rq.questions_posted,
    rq.answers_posted,
    rq.avg_post_score,
    rq.last_activity,
    rq.q_bucket,
    rq.net_votes,
    rq.score_variant,
    rq.q_score,
    rq.actual_answer_count,
    rq.comment_count,
    rq.viewcount,
    rq.has_accepted,
    rq.accepted_score,
    rq.avg_all_answer_score,
    rq.top3_tags,
    rq.max_tag_popularity,
    rq.loc_rank,
    la.q_cnt as loc_q_cnt,
    la.avg_score_variant as loc_avg_score,
    la.p90_score_variant as loc_p90_score,
    la.hot_cnt as loc_hot_cnt,
    la.accepted_cnt as loc_accepted_cnt
  from ranked_questions rq
  left join location_agg la on la.location_norm = coalesce(rq.owner_location,'Unknown')
),
final_scored as (
  select
    c.*,
    /* composite score: favor accepted, higher net votes, normalized by location p90, penalize duplicates/closed via bucket */
    (
      coalesce(c.score_variant,0) * 0.6
      + coalesce(c.net_votes,0) * 0.3
      + case when c.has_accepted = 1 then 10 else 0 end
      + least(coalesce(c.q_score,0), 50) * 0.1
      - case when c.q_bucket in ('duplicate','closed') then 15 else 0 end
      + case when c.loc_p90_score > 0 then (coalesce(c.score_variant,0) / c.loc_p90_score) * 5 else 0 end
    ) as composite_score
  from cross_loc_compare c
),
top_and_bottom as (
  select * from final_scored
  qualify row_number() over (order by composite_score desc, qid) <= 200
  union all
  select * from final_scored
  qualify row_number() over (order by composite_score asc, qid) <= 200
),
with_comments_and_events as (
  select
    t.qid,
    t.owner_name,
    t.owner_location,
    t.owner_reputation,
    t.total_badges,
    t.gold_badges,
    t.silver_badges,
    t.bronze_badges,
    t.questions_posted,
    t.answers_posted,
    t.avg_post_score,
    t.last_activity,
    t.q_bucket,
    t.net_votes,
    t.score_variant,
    t.q_score,
    t.actual_answer_count,
    t.comment_count,
    t.viewcount,
    t.has_accepted,
    t.accepted_score,
    t.avg_all_answer_score,
    t.top3_tags,
    t.max_tag_popularity,
    t.loc_rank,
    t.loc_q_cnt,
    t.loc_avg_score,
    t.loc_p90_score,
    t.loc_hot_cnt,
    t.loc_accepted_cnt,
    t.composite_score,
    coalesce(cs.avg_comment_score, 0) as avg_comment_score,
    cs.last_comment_date,
    crn.close_reason_name,
    cr.close_reason_comment
  from top_and_bottom t
  left join comment_stats cs on cs.postid = t.qid
  left join close_reasons cr on cr.qid = t.qid
  left join close_reason_name crn on crn.qid = t.qid
)
select
  qid,
  owner_name,
  owner_location,
  owner_reputation,
  total_badges,
  gold_badges,
  silver_badges,
  bronze_badges,
  questions_posted,
  answers_posted,
  avg_post_score,
  last_activity,
  q_bucket,
  net_votes,
  score_variant,
  q_score,
  actual_answer_count,
  comment_count,
  avg_comment_score,
  viewcount,
  has_accepted,
  accepted_score,
  avg_all_answer_score,
  top3_tags,
  max_tag_popularity,
  loc_rank,
  loc_q_cnt,
  loc_avg_score,
  loc_p90_score,
  loc_hot_cnt,
  loc_accepted_cnt,
  composite_score,
  last_comment_date,
  close_reason_name,
  close_reason_comment
from with_comments_and_events
order by composite_score desc, qid;