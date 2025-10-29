-- {"query": "62.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3293} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm
    from users u
    where u.creationdate >= (select date_trunc('month', max(p.creationdate)) - interval '12 months' from posts p)
),
badge_rollup as (
    select b.userid,
           count(*) as badge_count,
           sum(case when b.class = 1 then 1 else 0 end) as gold_count,
           sum(case when b.class = 2 then 1 else 0 end) as silver_count,
           sum(case when b.class = 3 then 1 else 0 end) as bronze_count,
           max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
q as (
    select p.id,
           p.owneruserid as user_id,
           p.creationdate,
           p.score,
           p.viewcount,
           p.title,
           p.tags,
           p.answercount,
           p.closeddate,
           p.favoritecount
    from posts p
    where p.posttypeid = 1
),
a as (
    select p.id,
           p.parentid as question_id,
           p.owneruserid as user_id,
           p.creationdate,
           p.score
    from posts p
    where p.posttypeid = 2
),
answers_agg as (
    select a.question_id,
           count(*) as answers_total,
           count(*) filter (where a.score > 0) as answers_positive,
           max(a.score) as max_answer_score,
           min(a.score) as min_answer_score,
           avg(a.score::numeric) as avg_answer_score,
           max(a.creationdate) as last_answer_date
    from a
    group by a.question_id
),
q_votes as (
    select v.postid as question_id,
           sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
           sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
           sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
           sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
    from votes v
    join q on q.id = v.postid
    group by v.postid
),
first_last_titles as (
    select ph.postid as question_id,
           min(ph.creationdate) filter (where ph.posthistorytypeid in (1,4)) as first_title_edit,
           max(ph.creationdate) filter (where ph.posthistorytypeid in (4,7)) as last_title_edit
    from posthistory ph
    where ph.posthistorytypeid in (1,4,7)
    group by ph.postid
),
closure_reasons as (
    select ph.postid as question_id,
           max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as closed_when,
           max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as reopened_when,
           max(case
                 when ph.posthistorytypeid = 10 then
                   case
                     when ph.comment ~ '^[0-9]+$' then ph.comment
                     else null
                   end
               end) as close_reason_raw
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
duplicates as (
    select pl.postid as dup_post_id,
           pl.relatedpostid as canonical_id,
           min(pl.creationdate) as first_link_date,
           count(*) as link_count
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid, pl.relatedpostid
),
tags_expanded as (
    select q.id as question_id,
           unnest(string_to_array(substring(q.tags from 2 for length(q.tags)-2), '><')) as tag
    from q
    where q.tags is not null and length(q.tags) > 2
),
tag_stats as (
    select te.question_id,
           count(*) as tag_count,
           sum(case when t.isrequired then 1 else 0 end) as required_tag_cnt,
           sum(case when t.ismoderatoronly then 1 else 0 end) as modonly_tag_cnt,
           sum(coalesce(t.count,0)) as total_tag_usage
    from tags_expanded te
    left join tags t on lower(t.tagname) = lower(te.tag)
    group by te.question_id
),
comment_sentiment as (
    select c.postid as question_id,
           count(*) as comment_count,
           sum(case when c.score > 0 then 1 else 0 end) as pos_comments,
           sum(case when c.score < 0 then 1 else 0 end) as neg_comments,
           avg(nullif(length(c.text),0)) as avg_comment_len,
           max(c.creationdate) as last_comment_date
    from comments c
    join q on q.id = c.postid
    group by c.postid
),
user_activity as (
    select p.owneruserid as user_id,
           count(*) filter (where p.posttypeid = 1) as q_count,
           count(*) filter (where p.posttypeid = 2) as a_count,
           max(p.lastactivitydate) as last_post_activity,
           sum(coalesce(p.score,0)) as total_post_score
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
canonical_q as (
    select q.id as question_id,
           case
             when d.canonical_id is not null then d.canonical_id
             else q.id
           end as canonical_id
    from q
    left join duplicates d on d.dup_post_id = q.id
),
clusters as (
    select cq.canonical_id,
           count(*) as cluster_size,
           min(q.creationdate) as cluster_first_created,
           max(q.creationdate) as cluster_last_created,
           sum(coalesce(q.score,0)) as cluster_score_sum
    from canonical_q cq
    join q on q.id = cq.question_id
    group by cq.canonical_id
),
question_metrics as (
    select
        q.id as question_id,
        q.user_id,
        q.creationdate,
        q.score,
        q.viewcount,
        q.title,
        q.tags,
        q.answercount,
        q.closeddate,
        q.favoritecount,
        qa.answers_total,
        qa.answers_positive,
        qa.max_answer_score,
        qa.min_answer_score,
        qa.avg_answer_score,
        qv.upvotes,
        qv.downvotes,
        qv.favorites as votes_favorites,
        qv.bounty_total,
        flt.first_title_edit,
        flt.last_title_edit,
        cr.closed_when,
        cr.reopened_when,
        cr.close_reason_raw,
        ts.tag_count,
        ts.required_tag_cnt,
        ts.modonly_tag_cnt,
        ts.total_tag_usage,
        cs.comment_count,
        cs.pos_comments,
        cs.neg_comments,
        cs.avg_comment_len,
        cs.last_comment_date,
        cq.canonical_id,
        cl.cluster_size,
        cl.cluster_first_created,
        cl.cluster_last_created,
        cl.cluster_score_sum
    from q
    left join answers_agg qa on qa.question_id = q.id
    left join q_votes qv on qv.question_id = q.id
    left join first_last_titles flt on flt.question_id = q.id
    left join closure_reasons cr on cr.question_id = q.id
    left join tag_stats ts on ts.question_id = q.id
    left join comment_sentiment cs on cs.question_id = q.id
    left join canonical_q cq on cq.question_id = q.id
    left join clusters cl on cl.canonical_id = cq.canonical_id
),
user_enriched as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.creationdate as user_created,
        ru.location,
        ru.websiteurl_norm,
        coalesce(ba.badge_count,0) as badge_count,
        coalesce(ba.gold_count,0) as gold_count,
        coalesce(ba.silver_count,0) as silver_count,
        coalesce(ba.bronze_count,0) as bronze_count,
        ba.last_badge_date,
        ua.q_count,
        ua.a_count,
        ua.last_post_activity,
        ua.total_post_score
    from recent_users ru
    left join badge_rollup ba on ba.userid = ru.user_id
    left join user_activity ua on ua.user_id = ru.user_id
),
ranked_questions as (
    select
        qm.*,
        ue.displayname,
        ue.reputation,
        ue.location,
        ue.websiteurl_norm,
        ue.badge_count,
        ue.gold_count,
        ue.silver_count,
        ue.bronze_count,
        ue.q_count,
        ue.a_count,
        ue.total_post_score,
        coalesce(qm.upvotes,0) - coalesce(qm.downvotes,0) as net_votes,
        case when qm.answercount is null or qm.answercount = 0 then 1 else 0 end as is_unanswered,
        case when qm.closeddate is not null then 1 else 0 end as is_closed,
        case when qm.closed_when is not null and qm.reopened_when is null then 1 else 0 end as is_closed_only,
        case when qm.closed_when is not null and qm.reopened_when is not null then 1 else 0 end as is_reopened,
        width_bucket(coalesce(qm.viewcount,0), 0, greatest(coalesce(qm.viewcount,0),1), 10) as view_bucket_dynamic,
        ntile(10) over (order by coalesce(qm.viewcount,0) desc nulls last) as view_ntile_desc,
        dense_rank() over (order by coalesce(qm.score,0) desc, coalesce(qm.viewcount,0) desc) as score_dense_rank,
        row_number() over (partition by ue.user_id order by coalesce(qm.viewcount,0) desc, qm.creationdate desc) as rn_per_user,
        sum(coalesce(qm.viewcount,0)) over (partition by ue.user_id) as views_per_user_sum,
        avg(coalesce(qm.score,0)) over (partition by ue.user_id) as avg_score_per_user,
        lag(qm.creationdate) over (partition by ue.user_id order by qm.creationdate) as prev_q_date,
        lead(qm.creationdate) over (partition by ue.user_id order by qm.creationdate) as next_q_date
    from question_metrics qm
    left join user_enriched ue on ue.user_id = qm.user_id
),
scored as (
    select
        rq.*,
        (
            coalesce(rq.net_votes,0) * 2
          + coalesce(rq.bounty_total,0) * 0.01
          + coalesce(rq.viewcount,0) * 0.001
          + coalesce(rq.answers_positive,0) * 1.5
          + case when rq.is_unanswered = 1 then -5 else 0 end
          + case when rq.is_closed_only = 1 then -10 else 0 end
          + case when rq.is_reopened = 1 then 3 else 0 end
          + least(coalesce(rq.tag_count,0), 5) * 0.5
          + coalesce(rq.gold_count,0) * 0.2
          + coalesce(rq.silver_count,0) * 0.1
          + coalesce(rq.bronze_count,0) * 0.05
        ) as perf_score
    from ranked_questions rq
),
topk as (
    select *
    from scored
    qualify row_number() over (
        order by perf_score desc nulls last,
                 coalesce(viewcount,0) desc,
                 creationdate desc
    ) <= 500
),
null_logic_probe as (
    select
        t.question_id,
        case
            when t.title is null and t.tags is null then 'both_null'
            when t.title is null then 'title_null'
            when t.tags is null then 'tags_null'
            else 'none_null'
        end as null_case,
        coalesce(nullif(btrim(lower(t.title)), ''), '[no title]') as title_norm,
        coalesce(t.tags, '[no tags]') as tags_norm
    from topk t
),
dupe_chains as (
    select
        cq.canonical_id,
        count(distinct cq.question_id) as chain_len,
        max(q.creationdate) as chain_last_created
    from canonical_q cq
    join q on q.id = cq.question_id
    group by cq.canonical_id
)
select
    t.question_id,
    t.user_id,
    coalesce(t.displayname, '[unknown]') as owner_displayname,
    t.reputation,
    t.location,
    t.websiteurl_norm,
    t.creationdate as question_created,
    t.score,
    t.viewcount,
    t.net_votes,
    t.answercount,
    t.answers_total,
    t.answers_positive,
    t.max_answer_score,
    t.min_answer_score,
    t.avg_answer_score,
    t.upvotes,
    t.downvotes,
    t.votes_favorites,
    t.bounty_total,
    t.closeddate,
    t.closed_when,
    t.reopened_when,
    t.close_reason_raw,
    t.tag_count,
    t.required_tag_cnt,
    t.modonly_tag_cnt,
    t.total_tag_usage,
    t.comment_count,
    t.pos_comments,
    t.neg_comments,
    t.avg_comment_len,
    t.last_comment_date,
    nlp.null_case,
    nlp.title_norm,
    nlp.tags_norm,
    t.canonical_id,
    t.cluster_size,
    t.cluster_first_created,
    t.cluster_last_created,
    t.cluster_score_sum,
    coalesce(dc.chain_len,1) as dupe_chain_len,
    dc.chain_last_created,
    t.view_bucket_dynamic,
    t.view_ntile_desc,
    t.score_dense_rank,
    t.rn_per_user,
    t.views_per_user_sum,
    t.avg_score_per_user,
    t.prev_q_date,
    t.next_q_date,
    t.badge_count,
    t.gold_count,
    t.silver_count,
    t.bronze_count,
    t.q_count,
    t.a_count,
    t.total_post_score,
    t.perf_score
from topk t
left join null_logic_probe nlp on nlp.question_id = t.question_id
left join dupe_chains dc on dc.canonical_id = t.canonical_id
where (
    t.is_closed = 0
    or (t.is_closed = 1 and coalesce(t.reopened_when, t.closed_when) >= t.creationdate)
)
and (
    t.view_ntile_desc <= 9
    or t.perf_score > (
        select avg(perf_score) from scored s
        where s.creationdate >= (select min(creationdate) from topk)
    )
)
order by t.perf_score desc nulls last, t.viewcount desc nulls last, t.creationdate desc;