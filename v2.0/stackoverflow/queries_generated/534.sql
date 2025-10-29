-- {"query": "534.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3864} 
with
-- Recent active users with engagement metrics
recent_users as (
  select
    u.id as user_id,
    coalesce(nullif(trim(u.displayname), ''), concat('user-', u.id::varchar)) as display_name,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    u.location,
    u.websiteurl,
    u.upvotes,
    u.downvotes,
    u.views,
    count(b.id) filter (where b.class = 1) as gold_badges,
    count(b.id) filter (where b.class = 2) as silver_badges,
    count(b.id) filter (where b.class = 3) as bronze_badges,
    max(b.date) as last_badge_date,
    row_number() over (order by u.reputation desc, u.id) as rn_by_rep
  from users u
  left join badges b on b.userid = u.id
  where u.creationdate >= (select date_trunc('year', max(creationdate)) - interval '3 years' from users)
  group by u.id, u.displayname, u.reputation, u.creationdate, u.lastaccessdate, u.location, u.websiteurl, u.upvotes, u.downvotes, u.views
),
-- Questions with detailed metrics
question_metrics as (
  select
    q.id as question_id,
    q.owneruserid as owner_user_id,
    q.creationdate as question_date,
    q.score as question_score,
    q.viewcount as question_views,
    q.answercount,
    q.favoritecount,
    q.closeddate,
    q.title,
    q.tags,
    -- parse tags into array
    string_to_array(substring(q.tags, 2, length(q.tags)-2), '><') as tag_array,
    -- accepted answer latency
    (select a.creationdate - q.creationdate
     from posts a
     where a.id = q.acceptedanswerid) as time_to_accepted,
    -- first answer latency
    (select min(a.creationdate) - q.creationdate
     from posts a
     where a.parentid = q.id and a.posttypeid = 2) as time_to_first_answer,
    -- close reason if available from PostHistory
    (
      select crt.name
      from posthistory ph
      join closerreasontypes crt on crt.id = ph.comment::int
      where ph.postid = q.id and ph.posthistorytypeid = 10
      order by ph.creationdate desc
      limit 1
    ) as close_reason_name
  from posts q
  where q.posttypeid = 1
),
-- Answers with window stats per question
answer_metrics as (
  select
    a.id as answer_id,
    a.parentid as question_id,
    a.owneruserid as owner_user_id,
    a.creationdate,
    a.score,
    a.commentcount,
    a.communityowneddate,
    rank() over (partition by a.parentid order by a.score desc nulls last, a.creationdate asc) as score_rank_in_q,
    count(*) over (partition by a.parentid) as answers_in_q
  from posts a
  where a.posttypeid = 2
),
-- Votes summary per post
vote_summary as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
    sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
    min(v.creationdate) as first_vote_at,
    max(v.creationdate) as last_vote_at
  from votes v
  group by v.postid
),
-- Comments summary per post with text-derived heuristics
comment_summary as (
  select
    c.postid,
    count(*) as comments_count,
    sum(case when c.score > 0 then 1 else 0 end) as positive_comments,
    sum(case when c.text ilike any (array['%thanks%','%great%','%nice%']) then 1 else 0 end) as niceness_comments,
    max(c.creationdate) as last_comment_at
  from comments c
  group by c.postid
),
-- Linkage/duplication graph metrics
link_summary as (
  select
    pl.postid,
    sum(case when pl.linktypeid = 1 then 1 else 0 end) as linked_count,
    sum(case when pl.linktypeid = 3 then 1 else 0 end) as duplicate_of_count,
    count(*) filter (where pl.linktypeid = 3 and pl.postid = pl.relatedpostid) as self_dupe_anomaly
  from postlinks pl
  group by pl.postid
),
-- Tag popularity lookup
tag_popularity as (
  select
    t.tagname,
    t.count as tag_total_count,
    t.ismodulatoronly,
    t.isrequired
  from tags t
),
-- Expand question tags to rows
question_tags as (
  select
    qm.question_id,
    lower(trim(t)) as tagname
  from question_metrics qm
  left join lateral unnest(qm.tag_array) as t on true
),
-- Aggregate tag signals for each question
question_tag_signals as (
  select
    qt.question_id,
    sum(tp.tag_total_count) as sum_tag_popularity,
    avg(tp.tag_total_count::numeric) as avg_tag_popularity,
    max(tp.tag_total_count) as max_tag_popularity,
    count(*) filter (where coalesce(tp.isrequired, 0) = 1) as required_tag_count,
    count(*) filter (where coalesce(tp.ismodulatoronly, 0) = 1) as moderator_only_tag_count,
    count(*) as tag_count
  from question_tags qt
  left join tag_popularity tp on tp.tagname = qt.tagname
  group by qt.question_id
),
-- User activity around their questions/answers
user_post_activity as (
  select
    u.id as user_id,
    count(*) filter (where p.posttypeid = 1) as questions_count,
    count(*) filter (where p.posttypeid = 2) as answers_count,
    sum(case when p.posttypeid in (1,2) then coalesce(p.score,0) else 0 end) as total_score,
    avg(case when p.posttypeid in (1,2) then p.score end) as avg_score,
    max(p.lastactivitydate) as last_post_activity
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id
),
-- Combine question, votes, comments, links, and tag signals
question_enriched as (
  select
    qm.*,
    vs.upvotes as q_upvotes,
    vs.downvotes as q_downvotes,
    vs.bounty_started as q_bounty_started,
    vs.bounty_awarded as q_bounty_awarded,
    vs.first_vote_at as q_first_vote_at,
    vs.last_vote_at as q_last_vote_at,
    cs.comments_count as q_comments_count,
    cs.positive_comments as q_positive_comments,
    cs.niceness_comments as q_nice_comments,
    cs.last_comment_at as q_last_comment_at,
    ls.linked_count as q_linked_count,
    ls.duplicate_of_count as q_duplicate_of_count,
    qts.sum_tag_popularity,
    qts.avg_tag_popularity,
    qts.max_tag_popularity,
    qts.required_tag_count,
    qts.moderator_only_tag_count,
    qts.tag_count
  from question_metrics qm
  left join vote_summary vs on vs.postid = qm.question_id
  left join comment_summary cs on cs.postid = qm.question_id
  left join link_summary ls on ls.postid = qm.question_id
  left join question_tag_signals qts on qts.question_id = qm.question_id
),
-- Best answer per question by score, with tie-breaker on creationdate
best_answers as (
  select am.*
  from answer_metrics am
  where am.score_rank_in_q = 1
),
-- Enrich answers with votes and comments
answer_enriched as (
  select
    am.*,
    vs.upvotes as a_upvotes,
    vs.downvotes as a_downvotes,
    vs.bounty_started as a_bounty_started,
    vs.bounty_awarded as a_bounty_awarded,
    cs.comments_count as a_comments_count,
    cs.positive_comments as a_positive_comments,
    cs.niceness_comments as a_nice_comments
  from answer_metrics am
  left join vote_summary vs on vs.postid = am.answer_id
  left join comment_summary cs on cs.postid = am.answer_id
),
-- Correlate best answer to question owner for acceptance and latency
qa_correlation as (
  select
    qe.question_id,
    qe.owner_user_id as question_owner_id,
    qe.question_date,
    qe.title,
    qe.tags,
    qe.tag_count,
    qe.sum_tag_popularity,
    qe.avg_tag_popularity,
    qe.max_tag_popularity,
    qe.question_score,
    qe.question_views,
    qe.answercount,
    qe.favoritecount,
    qe.closeddate,
    qe.close_reason_name,
    qe.q_upvotes, qe.q_downvotes, qe.q_bounty_started, qe.q_bounty_awarded,
    qe.q_first_vote_at, qe.q_last_vote_at,
    qe.q_comments_count, qe.q_positive_comments, qe.q_nice_comments, qe.q_last_comment_at,
    qe.q_linked_count, qe.q_duplicate_of_count,
    qe.time_to_accepted,
    qe.time_to_first_answer,
    ba.answer_id as best_answer_id,
    ba.owner_user_id as best_answer_owner_id,
    ba.creationdate as best_answer_date,
    ba.score as best_answer_score,
    ba.answers_in_q,
    ae.a_upvotes, ae.a_downvotes, ae.a_bounty_started, ae.a_bounty_awarded,
    ae.a_comments_count, ae.a_positive_comments, ae.a_nice_comments,
    -- derived metrics
    case when qe.answercount > 0 then
      extract(epoch from coalesce(qe.time_to_accepted, qe.time_to_first_answer))::bigint
    else null end as seconds_to_resolution,
    case when qe.closeddate is not null then 1 else 0 end as is_closed,
    case when qe.close_reason_name ilike '%duplicate%' then 1 else 0 end as is_closed_duplicate,
    case when qe.answercount > 0 then 1 else 0 end as has_answers,
    case when qe.time_to_accepted is not null then 1 else 0 end as has_accepted
  from question_enriched qe
  left join best_answers ba on ba.question_id = qe.question_id
  left join answer_enriched ae on ae.answer_id = ba.answer_id
),
-- Build user pair features: question owner vs best answer owner
user_pair_features as (
  select
    qac.question_id,
    qac.best_answer_id,
    qac.question_owner_id,
    qac.best_answer_owner_id,
    ru.display_name as question_owner_name,
    bu.display_name as best_answer_owner_name,
    ru.reputation as q_owner_rep,
    bu.reputation as a_owner_rep,
    ru.gold_badges as q_owner_gold,
    bu.gold_badges as a_owner_gold,
    ru.silver_badges as q_owner_silver,
    bu.silver_badges as a_owner_silver,
    ru.bronze_badges as q_owner_bronze,
    bu.bronze_badges as a_owner_bronze,
    upa_q.questions_count as q_owner_questions,
    upa_q.answers_count as q_owner_answers,
    upa_a.questions_count as a_owner_questions,
    upa_a.answers_count as a_owner_answers,
    upa_q.total_score as q_owner_total_score,
    upa_a.total_score as a_owner_total_score,
    upa_q.avg_score as q_owner_avg_score,
    upa_a.avg_score as a_owner_avg_score,
    abs(coalesce(ru.reputation,0) - coalesce(bu.reputation,0)) as abs_rep_gap,
    (coalesce(bu.reputation,0) - coalesce(ru.reputation,0)) as rep_delta_a_minus_q,
    (coalesce(upa_a.answers_count,0) - coalesce(upa_q.answers_count,0)) as answers_delta,
    greatest(coalesce(ru.lastaccessdate, 'epoch'::timestamp), coalesce(bu.lastaccessdate, 'epoch'::timestamp)) as pair_last_seen
  from qa_correlation qac
  left join recent_users ru on ru.user_id = qac.question_owner_id
  left join recent_users bu on bu.user_id = qac.best_answer_owner_id
  left join user_post_activity upa_q on upa_q.user_id = qac.question_owner_id
  left join user_post_activity upa_a on upa_a.user_id = qac.best_answer_owner_id
),
-- Flag potentially interesting anomalies
anomalies as (
  select
    qac.question_id,
    qac.best_answer_id,
    case when qac.has_answers = 1 and qac.seconds_to_resolution is null then 1 else 0 end as has_answers_but_no_latency,
    case when qac.has_answers = 1 and qac.best_answer_id is null then 1 else 0 end as has_answers_but_no_best,
    case when qac.is_closed = 1 and coalesce(qac.q_duplicate_of_count,0) = 0 and coalesce(qac.close_reason_name,'') = '' then 1 else 0 end as closed_without_reason,
    case when coalesce(qac.q_upvotes,0) < coalesce(qac.q_downvotes,0) then 1 else 0 end as more_downvotes_than_upvotes,
    case when qac.tag_count is null or qac.tag_count = 0 then 1 else 0 end as no_tags,
    case when qac.answercount > 10 and coalesce(qac.seconds_to_resolution,0) < 60 then 1 else 0 end as many_answers_very_fast
  from qa_correlation qac
)
select
  qac.question_id,
  left(coalesce(qac.title,''), 120) as title_preview,
  coalesce(qac.tags,'') as tags,
  qac.question_date,
  qac.question_views,
  qac.question_score,
  qac.answercount,
  qac.favoritecount,
  qac.is_closed,
  qac.is_closed_duplicate,
  qac.close_reason_name,
  qac.q_upvotes, qac.q_downvotes, qac.q_comments_count,
  qac.seconds_to_resolution,
  qac.has_accepted,
  qpf.question_owner_id,
  qpf.question_owner_name,
  qpf.q_owner_rep,
  qpf.q_owner_gold, qpf.q_owner_silver, qpf.q_owner_bronze,
  qpf.q_owner_questions, qpf.q_owner_answers,
  qpf.q_owner_total_score, qpf.q_owner_avg_score,
  qpf.best_answer_owner_id,
  qpf.best_answer_owner_name,
  qpf.a_owner_rep,
  qpf.a_owner_gold, qpf.a_owner_silver, qpf.a_owner_bronze,
  qpf.a_owner_questions, qpf.a_owner_answers,
  qpf.a_owner_total_score, qpf.a_owner_avg_score,
  qpf.abs_rep_gap, qpf.rep_delta_a_minus_q, qpf.answers_delta,
  qac.best_answer_id,
  qac.best_answer_score,
  qac.q_bounty_started, qac.q_bounty_awarded,
  qac.q_first_vote_at, qac.q_last_vote_at, qac.q_last_comment_at,
  qac.q_linked_count, qac.q_duplicate_of_count,
  qac.sum_tag_popularity, qac.avg_tag_popularity, qac.max_tag_popularity, qac.tag_count,
  a.has_answers_but_no_latency,
  a.has_answers_but_no_best,
  a.closed_without_reason,
  a.more_downvotes_than_upvotes,
  a.no_tags,
  a.many_answers_very_fast,
  -- normalized difficulty proxy
  round(
    coalesce(qac.question_views::numeric / nullif(qac.answercount,0), qac.question_views::numeric)
    / nullif(nullif(qac.avg_tag_popularity,0),0)
    , 4
  ) as difficulty_proxy,
  -- string-based hash bucketing for title/tags
  mod(abs(hashtext(coalesce(qac.title,'') || '|' || coalesce(qac.tags,''))), 97) as hash_bucket_97
from qa_correlation qac
left join user_pair_features qpf on qpf.question_id = qac.question_id
left join anomalies a on a.question_id = qac.question_id
where
  -- complex predicate mixing null checks, pattern matching, and arithmetic
  (
    (qac.question_views > 1000 and coalesce(qac.answercount,0) >= 1)
    or (qac.is_closed = 1 and qac.question_score <= 0)
    or (qac.tag_count >= 5 and qac.q_upvotes >= 10)
    or (qac.time_to_first_answer is not null and extract(epoch from qac.time_to_first_answer) between 0 and 3600)
  )
  and coalesce(qac.q_downvotes,0) <= (coalesce(qac.q_upvotes,0) + 5)
  and not (qac.close_reason_name ilike any (array['%spam%','%rude%']) )
  and (qac.tags is null or qac.tags !~* '<(?:homework|survey)>')
order by
  qac.is_closed asc,
  qac.has_accepted desc,
  qac.question_views desc,
  qac.question_date desc
limit 500;