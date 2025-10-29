with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'unknown') as domain_norm
    from users u
    where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '24 months' from users)
),
tagged_questions as (
    select p.id as qid,
           p.owneruserid,
           p.creationdate,
           p.score,
           p.viewcount,
           p.title,
           p.tags,
           array_length(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><'), 1) as tag_count
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= (select date_trunc('month', max(creationdate)) - interval '24 months' from posts)
),
answers as (
    select a.id as aid,
           a.parentid as qid,
           a.owneruserid as answerer_id,
           a.creationdate as answer_created,
           a.score as answer_score
    from posts a
    where a.posttypeid = 2
),
votes_agg as (
    select v.postid,
           sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
           sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
           sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
           sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
           count(*) as total_votes
    from votes v
    where v.creationdate >= (select date_trunc('month', max(creationdate)) - interval '24 months' from votes)
    group by v.postid
),
comments_agg as (
    select c.postid,
           count(*) as comment_count,
           sum(case when c.score > 0 then 1 else 0 end) as pos_comments,
           max(c.creationdate) as last_comment_at
    from comments c
    group by c.postid
),
links as (
    select pl.postid,
           sum(case when pl.linktypeid = 1 then 1 else 0 end) as linked_count,
           sum(case when pl.linktypeid = 3 then 1 else 0 end) as duplicate_count
    from postlinks pl
    group by pl.postid
),
close_events as (
    select ph.postid,
           min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_closed_at,
           max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopened_at,
           max(case when ph.posthistorytypeid = 10 then nullif(ph.comment, '') end) as last_close_reason_id
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
user_badge_rank as (
    select b.userid,
           count(*) filter (where b.class = 1) as gold,
           count(*) filter (where b.class = 2) as silver,
           count(*) filter (where b.class = 3) as bronze,
           row_number() over (partition by b.userid order by count(*) filter (where b.class = 1) desc, count(*) filter (where b.class = 2) desc, count(*) filter (where b.class = 3) desc, max(b.date) desc) as rn
    from badges b
    group by b.userid
),
tag_extract as (
    select q.qid,
           unnest(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><')) as tagname
    from tagged_questions q
),
tag_stats as (
    select te.qid,
           count(*) as tags_counted,
           min(t.count) as min_tag_popularity,
           max(t.count) as max_tag_popularity,
           avg(cast(t.count as numeric)) as avg_tag_popularity
    from tag_extract te
    left join tags t on lower(t.tagname) = lower(te.tagname)
    group by te.qid
),
answerer_first_answer as (
    select a.answerer_id,
           min(a.answer_created) as first_answer_at
    from answers a
    group by a.answerer_id
),
question_answer_metrics as (
    select q.qid,
           count(distinct a.aid) as answers_count,
           sum(case when a.answer_created <= q.creationdate + interval '7 days' then 1 else 0 end) as answers_in_week,
           max(a.answer_score) as max_answer_score,
           min(a.answer_created) as first_answer_at,
           max(a.answer_created) as last_answer_at,
           count(distinct a.answerer_id) as unique_answerers
    from tagged_questions q
    left join answers a on a.qid = q.qid
    group by q.qid
),
owner_activity as (
    select q.qid,
           u.id as owner_id,
           u.reputation,
           u.upvotes,
           u.downvotes,
           u.views as profile_views,
           ru.domain_norm as website_domain,
           coalesce(nullif(u.location,''), 'Unknown') as location_norm
    from tagged_questions q
    left join users u on u.id = q.owneruserid
    left join recent_users ru on ru.user_id = q.owneruserid
),
accepted_answer as (
    select q.id as qid,
           q.acceptedanswerid as accepted_id
    from posts q
    where q.posttypeid = 1
),
accept_timing as (
    select a.qid,
           case when aa.accepted_id is not null then 1 else 0 end as has_accepted,
           min(case when p.id = aa.accepted_id then p.creationdate end) as accepted_created_at
    from answers a
    join posts p on p.id = a.aid
    left join accepted_answer aa on aa.qid = a.qid
    group by a.qid, aa.accepted_id
),
quality_score as (
    select q.qid,
           coalesce(v.upvotes,0) - coalesce(v.downvotes,0) as net_votes,
           coalesce(v.total_votes,0) as total_votes,
           coalesce(l.linked_count,0) as linked_refs,
           coalesce(l.duplicate_count,0) as dup_refs,
           coalesce(c.comment_count,0) as comments,
           case when coalesce(v.total_votes,0) = 0 then null
                else (cast(coalesce(v.upvotes,0) as numeric) / nullif(coalesce(v.total_votes,0),0)) end as upvote_ratio
    from tagged_questions q
    left join votes_agg v on v.postid = q.qid
    left join links l on l.postid = q.qid
    left join comments_agg c on c.postid = q.qid
),
question_window as (
    select q.qid,
           q.owneruserid,
           q.creationdate,
           q.score,
           q.viewcount,
           q.title,
           q.tags,
           q.tag_count,
           row_number() over (partition by q.owneruserid order by q.creationdate desc, q.qid desc) as rn_owner_recent,
           dense_rank() over (order by q.creationdate desc) as recency_rank_global
    from tagged_questions q
),
-- compute global p50_views separately (no OVER on ordered-set aggregate)
global_view_stats as (
    select percentile_cont(0.5) within group (order by viewcount) as p50_views_global
    from tagged_questions
),
owner_post_mix as (
    select u.id as owner_id,
           count(*) filter (where p.posttypeid = 1) as questions,
           count(*) filter (where p.posttypeid = 2) as answers,
           sum(p.score) as total_post_score
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
question_flags as (
    select q.qid,
           case when q.viewcount > g.p50_views_global then 1 else 0 end as high_view_flag,
           case when qa.answers_count >= 5 then 1 else 0 end as many_answers_flag,
           case when ce.first_closed_at is not null then 1 else 0 end as ever_closed_flag
    from tagged_questions q
    cross join global_view_stats g
    left join question_answer_metrics qa on qa.qid = q.qid
    left join close_events ce on ce.postid = q.qid
),
base as (
    select
        qw.qid,
        qw.owneruserid,
        ru.displayname as owner_displayname,
        oa.location_norm,
        oa.website_domain,
        qb.gold,
        qb.silver,
        qb.bronze,
        qw.creationdate as question_created,
        qw.score as question_score,
        qw.viewcount,
        qw.title,
        lower(coalesce(qw.tags,'')) as tags_lower,
        ts.avg_tag_popularity,
        ts.max_tag_popularity,
        ts.min_tag_popularity,
        qa.answers_count,
        qa.answers_in_week,
        qa.first_answer_at,
        qa.last_answer_at,
        am.has_accepted,
        am.accepted_created_at,
        qs.net_votes,
        qs.total_votes,
        qs.linked_refs,
        qs.dup_refs,
        qs.comments,
        qs.upvote_ratio,
        qp.questions as owner_questions_total,
        qp.answers as owner_answers_total,
        qp.total_post_score as owner_total_post_score,
        qf.high_view_flag,
        qf.many_answers_flag,
        qf.ever_closed_flag,
        ce.first_closed_at,
        ce.last_reopened_at,
        ce.last_close_reason_id,
        vw.last_comment_at,
        qw.rn_owner_recent,
        qw.recency_rank_global
    from question_window qw
    left join recent_users ru on ru.user_id = qw.owneruserid
    left join owner_activity oa on oa.qid = qw.qid
    left join (select * from user_badge_rank where rn = 1) qb on qb.userid = qw.owneruserid
    left join tag_stats ts on ts.qid = qw.qid
    left join question_answer_metrics qa on qa.qid = qw.qid
    left join accept_timing am on am.qid = qw.qid
    left join quality_score qs on qs.qid = qw.qid
    left join owner_post_mix qp on qp.owner_id = qw.owneruserid
    left join question_flags qf on qf.qid = qw.qid
    left join close_events ce on ce.postid = qw.qid
    left join comments_agg vw on vw.postid = qw.qid
),
ranked as (
    select
        b.*,
        coalesce(b.net_votes,0) + coalesce(b.linked_refs,0) * 0.5 + coalesce(b.viewcount,0) / 1000.0
        + case when b.has_accepted = 1 then 2 else 0 end
        - coalesce(b.dup_refs,0) * 2
        - case when b.ever_closed_flag = 1 then 1 else 0 end
        + coalesce(b.avg_tag_popularity,0) / 10000.0
        as composite_score,
        rank() over (order by
            coalesce(b.net_votes, -999999) desc,
            coalesce(b.viewcount, -1) desc,
            coalesce(b.answers_count, -1) desc,
            b.qid desc
        ) as rnk_popular,
        dense_rank() over (partition by coalesce(b.website_domain,'unknown') order by coalesce(b.viewcount,0) desc) as rnk_by_domain
    from base b
),
domain_rollup as (
    select
        coalesce(website_domain,'unknown') as website_domain,
        count(*) as q_count,
        avg(cast(viewcount as numeric)) as avg_views,
        sum(case when has_accepted = 1 then 1 else 0 end) as accepted_qs,
        sum(composite_score) as composite_sum
    from ranked
    group by coalesce(website_domain,'unknown')
),
final_mix as (
    select
        r.*,
        dr.avg_views as domain_avg_views,
        dr.q_count as domain_q_count,
        dr.accepted_qs as domain_accepted_qs,
        dr.composite_sum as domain_composite_sum
    from ranked r
    left join domain_rollup dr on dr.website_domain = coalesce(r.website_domain,'unknown')
),
-- compute global 95th percentile for composite_score without OVER
global_composite_95 as (
    select percentile_cont(0.95) within group (order by composite_score) as p95_composite
    from ranked
)
select *
from (
    select
        fm.qid,
        fm.owneruserid,
        fm.owner_displayname,
        fm.location_norm,
        fm.website_domain,
        fm.gold, fm.silver, fm.bronze,
        fm.question_created,
        fm.question_score,
        fm.viewcount,
        fm.title,
        fm.tags_lower,
        fm.avg_tag_popularity,
        fm.max_tag_popularity,
        fm.min_tag_popularity,
        fm.answers_count,
        fm.answers_in_week,
        fm.first_answer_at,
        fm.last_answer_at,
        fm.has_accepted,
        fm.accepted_created_at,
        fm.net_votes,
        fm.total_votes,
        fm.linked_refs,
        fm.dup_refs,
        fm.comments,
        fm.upvote_ratio,
        fm.owner_questions_total,
        fm.owner_answers_total,
        fm.owner_total_post_score,
        fm.high_view_flag,
        fm.many_answers_flag,
        fm.ever_closed_flag,
        fm.first_closed_at,
        fm.last_reopened_at,
        fm.last_close_reason_id,
        fm.last_comment_at,
        fm.rn_owner_recent,
        fm.recency_rank_global,
        fm.composite_score,
        fm.rnk_popular,
        fm.rnk_by_domain,
        fm.domain_avg_views,
        fm.domain_q_count,
        fm.domain_accepted_qs,
        fm.domain_composite_sum,
        case
            when fm.upvote_ratio is null then 'no_votes'
            when fm.upvote_ratio >= 0.9 then 'loved'
            when fm.upvote_ratio >= 0.7 then 'liked'
            when fm.upvote_ratio >= 0.5 then 'mixed'
            else 'controversial'
        end as sentiment_bucket,
        case
            when fm.tags_lower like '%<sql>%' then 1
            when fm.tags_lower like '%<postgresql>%' then 1
            when fm.tags_lower like '%<mysql>%' then 1
            else 0
        end as is_db_related
    from final_mix fm
    left join global_composite_95 g95 on 1=1
    where (fm.rnk_popular <= 500 or fm.composite_score >= g95.p95_composite)
) s
where coalesce(s.owner_displayname, '') is distinct from ''
  and not (s.ever_closed_flag = 1 and s.has_accepted = 0)
order by s.composite_score desc, s.viewcount desc, s.qid desc
limit 1000 offset 0;