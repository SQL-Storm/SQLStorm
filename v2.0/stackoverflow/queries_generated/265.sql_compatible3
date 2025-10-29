with recent_users as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
    extract(year from u.creationdate) as signup_year
  from users u
  where u.creationdate >= (select max(p.creationdate) - interval '365 days' from posts p)
),
question_posts as (
  select
    p.id,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.title,
    p.tags,
    p.acceptedanswerid,
    p.closeddate,
    p.favoritecount,
    p.commentcount
  from posts p
  where p.posttypeid = 1
),
answer_posts as (
  select
    a.id,
    a.parentid as question_id,
    a.owneruserid as answerer_id,
    a.creationdate,
    a.score as answer_score
  from posts a
  where a.posttypeid = 2
),
tag_expanded as (
  select
    qp.id as question_id,
    unnest(string_to_array(substring(qp.tags, 2, length(qp.tags)-2), '><')) as tag
  from question_posts qp
  where qp.tags is not null and qp.tags like '<%>'
),
per_user_activity as (
  select
    ru.id as user_id,
    count(distinct qp.id) filter (where qp.owneruserid = ru.id) as questions_authored,
    count(distinct ap.id) filter (where ap.answerer_id = ru.id) as answers_authored,
    sum(greatest(qp.score, 0)) filter (where qp.owneruserid = ru.id) as q_score_pos,
    sum(greatest(ap.answer_score, 0)) filter (where ap.answerer_id = ru.id) as a_score_pos,
    sum(least(qp.score, 0)) filter (where qp.owneruserid = ru.id) as q_score_neg,
    sum(least(ap.answer_score, 0)) filter (where ap.answerer_id = ru.id) as a_score_neg,
    count(distinct case when qp.acceptedanswerid is not null and qp.owneruserid = ru.id then qp.id end) as q_with_accept,
    count(distinct case when ap.answerer_id = ru.id and ap.id = q.acceptedanswerid then ap.id end) as answers_accepted
  from recent_users ru
  left join question_posts qp on qp.owneruserid = ru.id
  left join answer_posts ap on ap.answerer_id = ru.id
  left join posts q on q.id = ap.question_id
  group by ru.id
),
vote_agg as (
  select
    v.userid as user_id,
    sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes_cast,
    count(*) filter (where v.votetypeid = 5) as favorites_made,
    count(*) filter (where v.votetypeid in (8,9)) as bounties_involved,
    sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as total_bounty_amount
  from votes v
  where v.userid is not null
  group by v.userid
),
comment_agg as (
  select
    c.userid as user_id,
    count(*) as comments_made,
    sum(c.score) as comment_score_sum,
    avg(c.score) filter (where c.score is not null) as comment_score_avg
  from comments c
  where c.userid is not null
  group by c.userid
),
badge_agg as (
  select
    b.userid as user_id,
    count(*) as badges_total,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    count(*) filter (where b.tagbased = true) as tag_badges
  from badges b
  group by b.userid
),
closure_info as (
  select
    ph.postid,
    min(ph.creationdate) as first_closed_at,
    max(ph.creationdate) as last_closed_at,
    -- convert comment to numeric-like text using regexp_replace to extract first numeric match (standard SQL-ish)
    NULLIF(regexp_replace(ph.comment, '.*?(-?[0-9]+(\.[0-9]+)?).*', '\1'), ph.comment) as common_close_reason_id
  from posthistory ph
  where ph.posthistorytypeid = 10
  group by ph.postid, ph.comment
),
hot_questions as (
  select distinct ph.postid
  from posthistory ph
  where ph.posthistorytypeid in (52)
),
dup_links as (
  select pl.postid as duplicate_of, pl.relatedpostid as original_of
  from postlinks pl
  where pl.linktypeid = 3
),
question_metrics as (
  select
    qp.id as question_id,
    qp.owneruserid as asker_id,
    qp.creationdate,
    qp.score,
    qp.viewcount,
    qp.favoritecount,
    qp.commentcount,
    coalesce(ci.first_closed_at, qp.closeddate) as closed_at_any,
    case when ci.postid is not null then 1 else 0 end as was_closed,
    case when hq.postid is not null then 1 else 0 end as was_hot,
    count(distinct ap.id) as answers_count,
    sum(case when ap.answer_score >= 0 then ap.answer_score else 0 end) as answers_pos_score,
    sum(case when ap.answer_score < 0 then ap.answer_score else 0 end) as answers_neg_score,
    count(distinct dl.original_of) as dup_targets_count
  from question_posts qp
  left join answer_posts ap on ap.question_id = qp.id
  left join closure_info ci on ci.postid = qp.id
  left join hot_questions hq on hq.postid = qp.id
  left join dup_links dl on dl.duplicate_of = qp.id
  group by qp.id, qp.owneruserid, qp.creationdate, qp.score, qp.viewcount, qp.favoritecount, qp.commentcount, ci.first_closed_at, qp.closeddate, hq.postid, ci.postid
),
tag_stats as (
  select
    te.tag,
    count(distinct te.question_id) as questions_with_tag,
    sum(qm.viewcount) as total_views,
    avg(qm.score) as avg_score,
    sum(case when qm.was_closed = 1 then 1 else 0 end) as closed_questions,
    sum(case when qm.was_hot = 1 then 1 else 0 end) as hot_questions
  from tag_expanded te
  join question_metrics qm on qm.question_id = te.question_id
  group by te.tag
),
user_tag_focus as (
  select
    qp.owneruserid as user_id,
    te.tag,
    count(*) as q_count,
    row_number() over (partition by qp.owneruserid order by count(*) desc, te.tag) as rn
  from question_posts qp
  join tag_expanded te on te.question_id = qp.id
  group by qp.owneruserid, te.tag
),
user_windows as (
  select
    ru.id as user_id,
    ru.displayname,
    ru.reputation,
    ru.location_norm,
    ru.signup_year,
    count(distinct qp.id) as q_cnt,
    count(distinct ap.id) as a_cnt,
    coalesce(avg(qp.score), 0) as avg_q_score,
    coalesce(avg(ap.answer_score), 0) as avg_a_score,
    percentile_cont(0.5) within group (order by qp.viewcount) as median_q_views,
    max(qp.viewcount) as max_q_views,
    min(qp.viewcount) as min_q_views
  from recent_users ru
  left join question_posts qp on qp.owneruserid = ru.id
  left join answer_posts ap on ap.answerer_id = ru.id
  group by ru.id, ru.displayname, ru.reputation, ru.location_norm, ru.signup_year
),
ranked_users as (
  select
    uw.*,
    row_number() over (order by coalesce(uw.a_cnt,0) * 2 + coalesce(uw.q_cnt,0) desc, uw.reputation desc) as activity_rank
  from user_windows uw
),
activity_rollup as (
  select
    ru.id as user_id,
    coalesce(pua.questions_authored,0) as questions_authored,
    coalesce(pua.answers_authored,0) as answers_authored,
    coalesce(pua.q_score_pos,0) + coalesce(pua.a_score_pos,0) as total_positive_score,
    coalesce(pua.q_score_neg,0) + coalesce(pua.a_score_neg,0) as total_negative_score,
    coalesce(pua.answers_accepted,0) as answers_accepted,
    coalesce(va.net_votes_cast,0) as net_votes_cast,
    coalesce(va.favorites_made,0) as favorites_made,
    coalesce(va.bounties_involved,0) as bounties_involved,
    coalesce(va.total_bounty_amount,0) as total_bounty_amount,
    coalesce(ca.comments_made,0) as comments_made,
    coalesce(ca.comment_score_sum,0) as comment_score_sum,
    ca.comment_score_avg,
    coalesce(ba.badges_total,0) as badges_total,
    coalesce(ba.gold_badges,0) as gold_badges,
    coalesce(ba.silver_badges,0) as silver_badges,
    coalesce(ba.bronze_badges,0) as bronze_badges,
    coalesce(ba.tag_badges,0) as tag_badges
  from recent_users ru
  left join per_user_activity pua on pua.user_id = ru.id
  left join vote_agg va on va.user_id = ru.id
  left join comment_agg ca on ca.user_id = ru.id
  left join badge_agg ba on ba.user_id = ru.id
),
final as (
  select
    r.activity_rank,
    ru.id as user_id,
    ru.displayname,
    ru.reputation,
    ru.location_norm,
    ru.signup_year,
    r.q_cnt,
    r.a_cnt,
    r.avg_q_score,
    r.avg_a_score,
    r.median_q_views,
    r.max_q_views,
    r.min_q_views,
    ar.questions_authored,
    ar.answers_authored,
    ar.total_positive_score,
    ar.total_negative_score,
    ar.answers_accepted,
    ar.net_votes_cast,
    ar.favorites_made,
    ar.bounties_involved,
    ar.total_bounty_amount,
    ar.comments_made,
    ar.comment_score_sum,
    ar.comment_score_avg,
    ar.badges_total,
    ar.gold_badges,
    ar.silver_badges,
    ar.bronze_badges,
    ar.tag_badges,
    utf.tag as top_tag,
    ts.questions_with_tag as top_tag_questions,
    ts.total_views as top_tag_total_views,
    ts.avg_score as top_tag_avg_score,
    ts.closed_questions as top_tag_closed_count,
    ts.hot_questions as top_tag_hot_count
  from ranked_users r
  join recent_users ru on ru.id = r.user_id
  left join activity_rollup ar on ar.user_id = r.user_id
  left join user_tag_focus utf on utf.user_id = r.user_id and utf.rn = 1
  left join tag_stats ts on ts.tag = utf.tag
)
select *
from final
where (coalesce(total_positive_score,0) + coalesce(total_negative_score,0)) <> 0
   or coalesce(a_cnt,0) + coalesce(q_cnt,0) > 0
order by activity_rank
limit 200;