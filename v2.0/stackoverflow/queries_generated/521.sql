-- {"query": "521.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3296} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl_norm,
        date_trunc('month', u.creationdate) as cohort_month,
        row_number() over (order by u.creationdate desc, u.id desc) as rn_global
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as questions,
        count(*) filter (where p.posttypeid = 2) as answers,
        sum(coalesce(p.score, 0)) as post_score_sum,
        avg(nullif(p.viewcount,0)) as avg_views_nonzero,
—
        max(p.creationdate) as last_post_date,
        sum(case when p.closeddate is not null then 1 else 0 end) as closed_posts
    from posts p
    where p.owneruserid is not null
      and p.creationdate >= (select min(creationdate) from recent_users)
    group by p.owneruserid
),
badges_by_user as (
    select
        b.userid as user_id,
        count(*) as total_badges,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
comment_stats as (
    select
        c.userid as user_id,
        count(*) as comments_count,
        sum(coalesce(c.score,0)) as comment_score_sum,
        max(c.creationdate) as last_comment_date
    from comments c
    where c.userid is not null
    group by c.userid
),
dup_links as (
    select
        pl.postid,
        count(*) filter (where pl.linktypeid = 3) as duplicate_links
    from postlinks pl
    group by pl.postid
),
question_quality as (
    select
        q.id as post_id,
        q.owneruserid as user_id,
        q.score,
        q.viewcount,
        q.favoritecount,
        q.answercount,
        q.acceptedanswerid,
        coalesce(dl.duplicate_links, 0) as duplicate_links,
        case
            when q.acceptedanswerid is not null then 1
            when q.answercount > 0 then 0.5
            else 0
        end
        + greatest(least(coalesce(q.score,0)::numeric / 10.0, 1.0), -1.0)
        + least(coalesce(q.viewcount,0)::numeric / 10000.0, 1.5)
        - least(coalesce(dl.duplicate_links,0)::numeric * 0.4, 2.0)
        as quality_score
    from posts q
    left join dup_links dl on dl.postid = q.id
    where q.posttypeid = 1
),
user_quality as (
    select
        qq.user_id,
        percentile_cont(0.5) within group (order by qq.quality_score) as median_q_quality,
        avg(qq.quality_score) as avg_q_quality,
        count(*) as questions_considered
    from question_quality qq
    group by qq.user_id
),
vote_summaries as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
        count(*) filter (where v.votetypeid in (10,12)) as deletion_or_spam_votes
    from votes v
    group by v.postid
),
last_close_reason as (
    select
        ph.postid,
        max(ph.creationdate) as last_close_event_date,
        cast(nullif(ph.comment, '') as int) as close_reason_id
    from posthistory ph
    where ph.posthistorytypeid = 10
    qualify row_number() over (partition by ph.postid order by ph.creationdate desc, ph.id desc) = 1
),
post_enriched as (
    select
        p.id,
        p.posttypeid,
        p.owneruserid as user_id,
        p.creationdate,
        p.score,
        p.viewcount,
        p.answercount,
        p.closeddate,
        p.title,
        p.tags,
        vs.upvotes,
        vs.downvotes,
        vs.bounty_total,
        vs.deletion_or_spam_votes,
        lcr.close_reason_id
    from posts p
    left join vote_summaries vs on vs.postid = p.id
    left join last_close_reason lcr on lcr.postid = p.id
),
cohort_activity as (
    select
        ru.cohort_month,
        count(distinct ru.user_id) as users_in_cohort,
        sum(coalesce(ua.questions,0)) as cohort_questions,
        sum(coalesce(ua.answers,0)) as cohort_answers,
        avg(coalesce(ua.post_score_sum,0)) as avg_post_score_sum,
        avg(coalesce(ua.avg_views_nonzero,0)) as avg_views_nonzero,
        sum(coalesce(ua.closed_posts,0)) as cohort_closed_posts
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    group by ru.cohort_month
),
ranked_users as (
    select
        ru.*,
        ua.questions,
        ua.answers,
        ua.post_score_sum,
        ua.avg_views_nonzero,
        ua.last_post_date,
        coalesce(ua.closed_posts,0) as closed_posts,
        coalesce(bu.total_badges,0) as total_badges,
        coalesce(bu.gold_badges,0) as gold_badges,
        coalesce(bu.silver_badges,0) as silver_badges,
        coalesce(bu.bronze_badges,0) as bronze_badges,
        bu.first_badge_date,
        bu.last_badge_date,
        coalesce(cs.comments_count,0) as comments_count,
        cs.comment_score_sum,
        cs.last_comment_date,
        uq.median_q_quality,
        uq.avg_q_quality,
        uq.questions_considered,
        row_number() over (
            partition by ru.cohort_month
            order by coalesce(ua.questions,0) + coalesce(ua.answers,0) desc,
                     coalesce(ua.post_score_sum,0) desc,
                     coalesce(bu.total_badges,0) desc,
                     ru.reputation desc,
                     ru.user_id desc
        ) as cohort_rank
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join badges_by_user bu on bu.user_id = ru.user_id
    left join comment_stats cs on cs.user_id = ru.user_id
    left join user_quality uq on uq.user_id = ru.user_id
),
stringified as (
    select
        r.user_id,
        r.displayname,
        r.reputation,
        r.location,
        r.websiteurl_norm,
        r.cohort_month,
        r.cohort_rank,
        r.questions,
        r.answers,
        r.post_score_sum,
        r.avg_views_nonzero,
        r.closed_posts,
        r.total_badges,
        r.gold_badges,
        r.silver_badges,
        r.bronze_badges,
        r.comments_count,
        r.comment_score_sum,
        coalesce(r.median_q_quality, 0) as median_q_quality,
        coalesce(r.avg_q_quality, 0) as avg_q_quality,
        coalesce(r.questions_considered, 0) as questions_considered,
        coalesce(to_char(r.first_badge_date, 'YYYY-MM-DD'), 'never') as first_badge_date_s,
        coalesce(to_char(r.last_badge_date, 'YYYY-MM-DD'), 'never') as last_badge_date_s,
        coalesce(to_char(r.last_post_date, 'YYYY-MM-DD'), 'none') as last_post_date_s,
        coalesce(to_char(r.last_comment_date, 'YYYY-MM-DD'), 'none') as last_comment_date_s,
        case
            when coalesce(r.questions,0) + coalesce(r.answers,0) = 0 then 'lurker'
            when coalesce(r.answers,0) >= 5 and coalesce(r.gold_badges,0) >= 1 then 'expert'
            when coalesce(r.questions,0) >= 3 and coalesce(r.answers,0) >= 3 then 'all-rounder'
            when coalesce(r.questions,0) >= 4 then 'inquisitive'
            when coalesce(r.answers,0) >= 4 then 'helper'
            else 'participant'
        end as role_bucket
    from ranked_users r
),
heavy_union as (
    select user_id, displayname, 'A' as src, reputation from stringified
    union all
    select user_id, displayname, 'B' as src, reputation from stringified where total_badges > 0
    union all
    select user_id, displayname, 'C' as src, reputation from stringified where comments_count > 0
),
dense_ranks as (
    select
        hu.user_id,
        min(src) as min_src,
        max(src) as max_src,
        dense_rank() over (order by sum(reputation) desc, min(src)) as dr
    from heavy_union hu
    group by hu.user_id
),
collapsed as (
    select
        s.*,
        d.dr,
        d.min_src || '-' || d.max_src as src_span,
        (coalesce(s.post_score_sum,0) + coalesce(s.comment_score_sum,0))::numeric
          / nullif(coalesce(s.questions,0) + coalesce(s.answers,0) + coalesce(s.comments_count,0),0) as avg_interaction_score
    from stringified s
    join dense_ranks d on d.user_id = s.user_id
),
cross_cohort as (
    select
        c1.cohort_month as cohort_a,
        c2.cohort_month as cohort_b,
        count(*) as pairs
    from cohort_activity c1
    join cohort_activity c2 on c1.cohort_month <= c2.cohort_month
    group by c1.cohort_month, c2.cohort_month
),
top_posts_per_user as (
    select
        pe.user_id,
        pe.id as post_id,
        pe.posttypeid,
        pe.score,
        pe.viewcount,
        pe.upvotes,
        pe.downvotes,
        pe.bounty_total,
        pe.deletion_or_spam_votes,
        pe.close_reason_id,
        row_number() over (
            partition by pe.user_id
            order by coalesce(pe.score,0) * 1.0
                   + coalesce(pe.upvotes,0) * 0.5
                   - coalesce(pe.downvotes,0) * 0.7
                   + least(coalesce(pe.viewcount,0) / 5000.0, 2.0)
                   + least(coalesce(pe.bounty_total,0) / 50.0, 3.0)
                   - coalesce(pe.deletion_or_spam_votes,0) * 2.0 desc,
                   pe.id desc
        ) as rn
    from post_enriched pe
),
accepted_ratio as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 2) as answers_total,
        count(*) filter (where p.posttypeid = 2 and exists (
            select 1 from posts q where q.id = p.parentid and q.acceptedanswerid = p.id
        )) as answers_accepted
    from posts p
    group by p.owneruserid
),
null_logic_probe as (
    select
        s.user_id,
        case
            when s.websiteurl_norm is null then 1
            when s.websiteurl_norm ilike 'http%' then 0
            else null
        end as web_flag_nullable,
        coalesce(nullif(s.location,''), 'Unknown') as location_norm
    from stringified s
)
select
    c.user_id,
    c.displayname,
    c.reputation,
    c.cohort_month,
    c.cohort_rank,
    c.role_bucket,
    c.dr as dense_rank_global,
    c.src_span,
    round(coalesce(c.avg_interaction_score,0), 4) as avg_interaction_score,
    c.questions,
    c.answers,
    c.total_badges,
    c.gold_badges,
    c.silver_badges,
    c.bronze_badges,
    c.median_q_quality,
    c.avg_q_quality,
    c.questions_considered,
    c.first_badge_date_s,
    c.last_badge_date_s,
    c.last_post_date_s,
    c.last_comment_date_s,
    ar.answers_total,
    ar.answers_accepted,
    case
        when ar.answers_total > 0 then round(ar.answers_accepted::numeric / ar.answers_total, 4)
        else null
    end as accepted_answer_ratio,
    nlp.web_flag_nullable,
    nlp.location_norm,
    tp.post_id as top_post_id,
    tp.posttypeid as top_post_type,
    tp.score as top_post_score,
    tp.viewcount as top_post_views,
    tp.bounty_total as top_post_bounty,
    tp.close_reason_id as top_post_last_close_reason_id,
    (select count(*) from cross_cohort where cohort_a = c.cohort_month) as cohorts_from_here,
    (select sum(pairs) from cross_cohort where cohort_b = c.cohort_month) as cohorts_to_here,
    (select string_agg(tag, ',')
     from (
         select distinct unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tag
         from posts p
         where p.owneruserid = c.user_id and p.posttypeid = 1 and p.tags is not null
         order by 1
     ) t
    ) as distinct_tags
from collapsed c
left join accepted_ratio ar on ar.user_id = c.user_id
left join null_logic_probe nlp on nlp.user_id = c.user_id
left join top_posts_per_user tp on tp.user_id = c.user_id and tp.rn = 1
where
    (c.reputation > 100 or c.total_badges > 3 or c.avg_q_quality > 0.3)
    and coalesce(c.questions,0) + coalesce(c.answers,0) + coalesce(c.comments_count,0) > 0
    and not (c.location ilike '%test%' or c.displayname ilike '%bot%')
order by
    c.dr asc,
    c.cohort_month desc,
    c.cohort_rank asc
limit 500;