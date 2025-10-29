-- {"query": "556.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2671} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.location,
           date_trunc('month', u.creationdate) as signup_month,
           coalesce(nullif(trim(u.websiteurl), ''), 'unknown') as normalized_site
    from users u
    where u.creationdate >= now() - interval '5 years'
),
question_posts as (
    select p.id as post_id,
           p.owneruserid as user_id,
           p.creationdate,
           p.score,
           p.viewcount,
           p.title,
           p.tags,
           p.answercount,
           p.favoritecount,
           p.closeddate,
           p.contentlicense
    from posts p
    where p.posttypeid = 1
),
answer_posts as (
    select p.id as post_id,
           p.parentid as question_id,
           p.owneruserid as user_id,
           p.creationdate,
           p.score as answer_score
    from posts p
    where p.posttypeid = 2
),
user_activity as (
    select ru.user_id,
           count(distinct qp.post_id) filter (where qp.creationdate >= now() - interval '3 years') as questions_3y,
           sum(qp.score) filter (where qp.creationdate >= now() - interval '3 years') as q_score_3y,
           count(distinct ap.post_id) filter (where ap.creationdate >= now() - interval '3 years') as answers_3y,
           sum(ap.answer_score) filter (where ap.creationdate >= now() - interval '3 years') as a_score_3y,
           count(distinct c.id) filter (where c.creationdate >= now() - interval '3 years') as comments_3y,
           sum(c.score) filter (where c.creationdate >= now() - interval '3 years') as c_score_3y
    from recent_users ru
    left join question_posts qp on qp.user_id = ru.user_id
    left join answer_posts ap on ap.user_id = ru.user_id
    left join comments c on c.userid = ru.user_id
    group by ru.user_id
),
first_last_q as (
    select qp.user_id,
           min(qp.creationdate) as first_q_date,
           max(qp.creationdate) as last_q_date
    from question_posts qp
    group by qp.user_id
),
q_tag_expansion as (
    select qp.post_id,
           qp.user_id,
           unnest(string_to_array(coalesce(substring(qp.tags, 2, greatest(length(qp.tags)-2,0)), ''), '><')) as tag
    from question_posts qp
),
user_top_tag as (
    select user_id,
           tag,
           count(*) as tag_count,
           row_number() over (partition by user_id order by count(*) desc, tag asc) as rn
    from q_tag_expansion
    group by user_id, tag
),
dup_chain as (
    select pl.postid as dup_post_id,
           pl.relatedpostid as canonical_post_id,
           pl.creationdate as link_date
    from postlinks pl
    where pl.linktypeid = 3
),
q_close_reasons as (
    select ph.postid as post_id,
           max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as closed_at,
           max(case when ph.posthistorytypeid = 10 then nullif(ph.comment, '') end) as close_reason_id_raw
    from posthistory ph
    where ph.posthistorytypeid in (10,11,12,13,35)
    group by ph.postid
),
vote_agg as (
    select v.postid,
           sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
           sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
           sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
           sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
           count(*) filter (where v.votetypeid in (10,11,12)) as mod_actions
    from votes v
    group by v.postid
),
q_metrics as (
    select qp.post_id,
           qp.user_id,
           qp.creationdate,
           qp.score,
           qp.viewcount,
           qp.answercount,
           qp.favoritecount,
           qa_cnt.answers as total_answers,
           va.upvotes,
           va.downvotes,
           coalesce(va.bounty_started,0) as bounty_started,
           coalesce(va.bounty_awarded,0) as bounty_awarded,
           qc.closed_at,
           qc.close_reason_id_raw,
           dc.canonical_post_id as duplicate_of,
           case when dc.canonical_post_id is not null then 1 else 0 end as is_duplicate
    from question_posts qp
    left join (
        select parentid as question_id, count(*) as answers
        from posts
        where posttypeid = 2
        group by parentid
    ) qa_cnt on qa_cnt.question_id = qp.post_id
    left join vote_agg va on va.postid = qp.post_id
    left join q_close_reasons qc on qc.post_id = qp.post_id
    left join dup_chain dc on dc.dup_post_id = qp.post_id
),
user_rankings as (
    select ru.user_id,
           ru.displayname,
           ru.reputation,
           ru.location,
           ru.signup_month,
           ru.normalized_site,
           ua.questions_3y,
           ua.q_score_3y,
           ua.answers_3y,
           ua.a_score_3y,
           ua.comments_3y,
           ua.c_score_3y,
           fl.first_q_date,
           fl.last_q_date,
           ut.tag as top_tag,
           ut.tag_count as top_tag_count,
           sum(qm.score) as lifetime_q_score,
           sum(qm.viewcount) as lifetime_q_views,
           sum(qm.total_answers) as lifetime_answers_rcvd,
           sum(qm.upvotes) as lifetime_q_upvotes,
           sum(qm.downvotes) as lifetime_q_downvotes,
           sum(qm.is_duplicate) as dup_count,
           count(*) filter (where qm.closed_at is not null) as closed_count,
           count(*) as total_questions,
           avg(qm.score) as avg_q_score,
           percentile_cont(0.5) within group (order by qm.viewcount) as median_q_views,
           max(qm.bounty_started) as max_bounty_started,
           max(qm.bounty_awarded) as max_bounty_awarded
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join first_last_q fl on fl.user_id = ru.user_id
    left join user_top_tag ut on ut.user_id = ru.user_id and ut.rn = 1
    left join q_metrics qm on qm.user_id = ru.user_id
    group by ru.user_id, ru.displayname, ru.reputation, ru.location, ru.signup_month, ru.normalized_site,
             ua.questions_3y, ua.q_score_3y, ua.answers_3y, ua.a_score_3y, ua.comments_3y, ua.c_score_3y,
             fl.first_q_date, fl.last_q_date, ut.tag, ut.tag_count
),
user_score as (
    select ur.*,
           case
               when ur.total_questions = 0 then 0
               else round(
                   0.30 * coalesce(ur.q_score_3y::numeric,0)
                 + 0.20 * coalesce(ur.a_score_3y::numeric,0)
                 + 0.10 * least(coalesce(ur.comments_3y,0), 500)
                 + 0.15 * coalesce(ur.lifetime_q_upvotes - ur.lifetime_q_downvotes,0)
                 + 0.10 * coalesce(ur.lifetime_answers_rcvd,0)
                 + 0.05 * greatest(coalesce(ur.lifetime_q_views,0)::numeric / greatest(ur.total_questions,1), 0)
                 - 0.15 * coalesce(ur.dup_count,0)
                 - 0.10 * coalesce(ur.closed_count,0)
                 , 2)
           end as engagement_score
    from user_rankings ur
),
site_peers as (
    select normalized_site,
           percentile_cont(0.25) within group (order by engagement_score) as p25,
           percentile_cont(0.50) within group (order by engagement_score) as p50,
           percentile_cont(0.75) within group (order by engagement_score) as p75
    from user_score
    group by normalized_site
),
badges_agg as (
    select b.userid as user_id,
           sum(case when b.class = 1 then 1 else 0 end) as golds,
           sum(case when b.class = 2 then 1 else 0 end) as silvers,
           sum(case when b.class = 3 then 1 else 0 end) as bronzes,
           count(*) filter (where b.date >= now() - interval '3 years') as badges_3y
    from badges b
    group by b.userid
),
commenter_sentiment as (
    select c.userid as user_id,
           avg(nullif(regexp_replace(lower(c.text), '[^a-z ]', '', 'g') like any (array['%thanks%','%great%','%helpful%','%appreciate%'])::int,0)) as pos_ratio,
           avg(nullif(regexp_replace(lower(c.text), '[^a-z ]', '', 'g') like any (array['%bad%','%wrong%','%terrible%','%hate%'])::int,0)) as neg_ratio
    from comments c
    where c.userid is not null
    group by c.userid
),
final as (
    select us.user_id,
           coalesce(nullif(trim(us.displayname), ''), ('user#' || us.user_id::text)) as displayname,
           us.reputation,
           us.location,
           us.signup_month,
           us.normalized_site,
           us.top_tag,
           us.top_tag_count,
           us.total_questions,
           us.lifetime_q_views,
           us.lifetime_q_upvotes,
           us.lifetime_q_downvotes,
           us.lifetime_answers_rcvd,
           us.q_score_3y,
           us.a_score_3y,
           us.comments_3y,
           us.c_score_3y,
           us.first_q_date,
           us.last_q_date,
           us.dup_count,
           us.closed_count,
           us.avg_q_score,
           us.median_q_views,
           us.max_bounty_started,
           us.max_bounty_awarded,
           us.engagement_score,
           sp.p25, sp.p50, sp.p75,
           case
               when us.engagement_score < sp.p25 then 'low'
               when us.engagement_score < sp.p50 then 'below_average'
               when us.engagement_score < sp.p75 then 'above_average'
               else 'high'
           end as peer_band,
           ba.golds, ba.silvers, ba.bronzes, ba.badges_3y,
           cs.pos_ratio, cs.neg_ratio,
           rank() over (order by us.engagement_score desc, us.lifetime_q_upvotes - us.lifetime_q_downvotes desc, us.reputation desc) as global_rank,
           dense_rank() over (partition by us.normalized_site order by us.engagement_score desc) as site_rank
    from user_score us
    left join site_peers sp on sp.normalized_site = us.normalized_site
    left join badges_agg ba on ba.user_id = us.user_id
    left join commenter_sentiment cs on cs.user_id = us.user_id
)
select f.*
from final f
where coalesce(f.total_questions,0) + coalesce(f.answers_3y,0) + coalesce(f.comments_3y,0) > 0
  and (f.reputation > 100 or f.engagement_score > 5)
  and (f.top_tag is null or length(f.top_tag) <= 35)
  and not (f.location ilike '%test%' or f.displayname ilike '%bot%')
order by f.global_rank
limit 250;