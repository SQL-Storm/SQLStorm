-- {"query": "885.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3191} 
with recent_activity as (
    select
        p.id as post_id,
        p.posttypeid,
        p.owneruserid,
        p.score,
        p.viewcount,
        p.answercount,
        p.favoritecount,
        p.tags,
        p.creationdate,
        p.lastactivitydate,
        coalesce(nullif(trim(p.title), ''), '(no title)') as safe_title,
        case when p.closeddate is not null then 1 else 0 end as is_closed
    from posts p
    where p.creationdate >= now() - interval '365 days'
),
user_stats as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate as user_created,
        u.upvotes,
        u.downvotes,
        u.views as profile_views,
        coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm
    from users u
),
comments_agg as (
    select
        c.postid,
        count(*) as comment_count,
        sum(case when c.score > 0 then 1 else 0 end) as pos_comment_count,
        max(c.creationdate) as last_comment_date,
        string_agg(distinct left(coalesce(nullif(trim(c.userdisplayname), ''), 'anon'), 20), ', ' order by left(coalesce(nullif(trim(c.userdisplayname), ''), 'anon'), 20)) as commenters
    from comments c
    where c.creationdate >= now() - interval '365 days'
    group by c.postid
),
votes_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
        count(*) filter (where v.votetypeid in (2,3,8,9)) as vote_events,
        max(v.creationdate) as last_vote_date
    from votes v
    where v.creationdate >= now() - interval '365 days'
    group by v.postid
),
tag_expansion as (
    select
        ra.post_id,
        unnest(string_to_array(substring(ra.tags, 2, length(ra.tags)-2), '><')) as tagname
    from recent_activity ra
    where ra.tags is not null
),
tag_rank as (
    select
        te.post_id,
        te.tagname,
        t.count as global_tag_count,
        row_number() over (partition by te.post_id order by coalesce(t.count, 0) desc, te.tagname asc) as tag_rank_desc_popularity,
        dense_rank() over (order by coalesce(t.count, 0) desc) as popularity_band
    from tag_expansion te
    left join tags t on lower(t.tagname) = lower(te.tagname)
),
primary_tag as (
    select post_id, tagname as primary_tag, coalesce(global_tag_count,0) as primary_tag_global_count
    from tag_rank
    where tag_rank_desc_popularity = 1
),
related_links as (
    select
        pl.postid,
        count(*) filter (where pl.linktypeid = 1) as linked_count,
        count(*) filter (where pl.linktypeid = 3) as duplicate_count,
        max(pl.creationdate) as last_link_date
    from postlinks pl
    where pl.creationdate >= now() - interval '365 days'
    group by pl.postid
),
edits_agg as (
    select
        ph.postid,
        count(*) filter (where ph.posthistorytypeid in (4,5,6)) as direct_edits,
        count(*) filter (where ph.posthistorytypeid in (24)) as suggested_edits,
        count(*) filter (where ph.posthistorytypeid in (10)) as close_votes_events,
        max(ph.creationdate) as last_edit_date,
        sum(case when ph.posthistorytypeid = 10 and ph.comment in ('101','102','103','104','105','1','2','3','4','7','10','20') then 1 else 0 end) as close_reason_count
    from posthistory ph
    where ph.creationdate >= now() - interval '365 days'
    group by ph.postid
),
answers as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as answerer_id,
        a.score as answer_score,
        a.creationdate as answer_created,
        row_number() over (partition by a.parentid order by a.score desc nulls last, a.creationdate asc) as rn_by_score
    from posts a
    where a.posttypeid = 2
),
top_answers as (
    select
        question_id,
        max(answer_score) filter (where rn_by_score = 1) as top_answer_score,
        min(answer_created) filter (where rn_by_score = 1) as top_answer_created,
        count(*) as total_answers
    from answers
    group by question_id
),
question_core as (
    select
        ra.post_id,
        ra.safe_title,
        ra.creationdate,
        ra.lastactivitydate,
        ra.score,
        ra.viewcount,
        ra.answercount,
        ra.favoritecount,
        ra.is_closed,
        pt.primary_tag,
        pt.primary_tag_global_count,
        coalesce(ta.top_answer_score, -2147483648) as top_answer_score,
        ta.top_answer_created,
        ta.total_answers
    from recent_activity ra
    left join primary_tag pt on pt.post_id = ra.post_id
    left join top_answers ta on ta.question_id = ra.post_id
    where ra.posttypeid = 1
),
user_enriched as (
    select
        us.user_id,
        us.displayname,
        us.reputation,
        us.user_created,
        us.upvotes,
        us.downvotes,
        us.profile_views,
        us.location_norm,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        count(b.id) as total_badges,
        max(b.date) as last_badge_date
    from user_stats us
    left join badges b on b.userid = us.user_id
    group by us.user_id, us.displayname, us.reputation, us.user_created, us.upvotes, us.downvotes, us.profile_views, us.location_norm
),
quality_scoring as (
    select
        qc.post_id,
        qc.safe_title,
        qc.creationdate,
        qc.lastactivitydate,
        qc.score,
        qc.viewcount,
        qc.answercount,
        qc.favoritecount,
        qc.is_closed,
        qc.primary_tag,
        qc.primary_tag_global_count,
        qc.top_answer_score,
        qc.top_answer_created,
        qc.total_answers,
        ua.user_id,
        ua.displayname,
        ua.reputation,
        ua.total_badges,
        ua.gold_badges,
        ua.silver_badges,
        ua.bronze_badges,
        ua.location_norm,
        ua.profile_views,
        ua.user_created,
        coalesce(ca.comment_count, 0) as comment_count,
        coalesce(ca.pos_comment_count, 0) as pos_comment_count,
        ca.last_comment_date,
        coalesce(va.upvotes, 0) as upvotes,
        coalesce(va.downvotes, 0) as downvotes,
        coalesce(va.bounty_started, 0) as bounty_started,
        coalesce(va.bounty_awarded, 0) as bounty_awarded,
        coalesce(rl.linked_count, 0) as linked_count,
        coalesce(rl.duplicate_count, 0) as duplicate_count,
        ea.direct_edits,
        ea.suggested_edits,
        ea.close_votes_events,
        ea.last_edit_date,
        case
            when qc.viewcount is null or qc.viewcount = 0 then null
            else round((qc.score::numeric + coalesce(va.upvotes,0) - coalesce(va.downvotes,0) + least(coalesce(ua.reputation,0)/100.0, 50)) / nullif(qc.viewcount::numeric, 0), 6)
        end as engagement_score,
        case
            when qc.answercount is null or qc.answercount = 0 then null
            else round((coalesce(qc.top_answer_score,0)::numeric + coalesce(va.upvotes,0) * 0.25 + coalesce(ca.pos_comment_count,0) * 0.1) / qc.answercount::numeric, 6)
        end as answer_quality_score,
        case
            when qc.favoritecount is null then 0
            else qc.favoritecount
        end as saves_proxy,
        regexp_replace(lower(coalesce(qc.safe_title, '(no title)')), '\s+', ' ', 'g') as norm_title
    from question_core qc
    left join posts p on p.id = qc.post_id
    left join user_enriched ua on ua.user_id = p.owneruserid
    left join comments_agg ca on ca.postid = qc.post_id
    left join votes_agg va on va.postid = qc.post_id
    left join related_links rl on rl.postid = qc.post_id
    left join edits_agg ea on ea.postid = qc.post_id
),
ranked as (
    select
        qs.*,
        row_number() over (order by coalesce(qs.engagement_score, -1) desc nulls last, qs.answer_quality_score desc nulls last, qs.viewcount desc nulls last, qs.creationdate desc) as rn_global,
        rank() over (partition by coalesce(qs.primary_tag, '(no tag)') order by coalesce(qs.engagement_score, -1) desc nulls last) as rn_by_tag,
        ntile(10) over (order by coalesce(qs.engagement_score, -1) desc nulls last) as decile_engagement
    from quality_scoring qs
),
anomalies as (
    select
        r.post_id,
        case
            when r.duplicate_count > 0 and r.upvotes > 50 and r.is_closed = 1 then 'High-upvote duplicate closed'
            when r.engagement_score is null and r.viewcount > 1000 then 'High views but no engagement'
            when r.answercount > 0 and r.top_answer_score is null then 'Answers but missing top score'
            when r.downvotes > r.upvotes and r.favoritecount > 10 then 'Many saves despite net negative'
            else null
        end as anomaly_reason
    from ranked r
),
final_set as (
    select
        r.post_id,
        r.safe_title,
        r.norm_title,
        r.primary_tag,
        r.primary_tag_global_count,
        r.creationdate,
        r.lastactivitydate,
        r.viewcount,
        r.score,
        r.upvotes,
        r.downvotes,
        r.answercount,
        r.total_answers,
        r.top_answer_score,
        r.top_answer_created,
        r.favoritecount as saves_proxy,
        r.comment_count,
        r.pos_comment_count,
        r.direct_edits,
        r.suggested_edits,
        r.close_votes_events,
        r.linked_count,
        r.duplicate_count,
        r.engagement_score,
        r.answer_quality_score,
        r.reputation,
        r.total_badges,
        r.gold_badges,
        r.silver_badges,
        r.bronze_badges,
        r.location_norm,
        r.profile_views,
        r.user_created,
        r.rn_global,
        r.rn_by_tag,
        r.decile_engagement,
        a.anomaly_reason
    from ranked r
    left join anomalies a on a.post_id = r.post_id
),
top_per_tag as (
    select *
    from final_set
    where rn_by_tag <= 25
),
bottom_outliers as (
    select *
    from final_set
    where decile_engagement = 10 and engagement_score is not null and answer_quality_score is not null
),
combined as (
    select * from top_per_tag
    union all
    select * from bottom_outliers
),
dedup as (
    select
        c.*,
        row_number() over (partition by c.post_id order by c.rn_global) as dedup_rn
    from combined c
)
select
    d.post_id,
    d.safe_title,
    d.primary_tag,
    d.primary_tag_global_count,
    d.creationdate,
    d.viewcount,
    d.score,
    d.upvotes,
    d.downvotes,
    d.answercount,
    d.total_answers,
    d.top_answer_score,
    d.engagement_score,
    d.answer_quality_score,
    d.rn_global,
    d.rn_by_tag,
    d.decile_engagement,
    coalesce(d.anomaly_reason, case when d.is_closed = 1 then 'Closed' end) as anomaly_or_closed,
    -- correlated subquery for duplicate-of title if exists
    (
        select coalesce(p2.title, '(no related title)')
        from postlinks pl2
        join posts p2 on p2.id = pl2.relatedpostid
        where pl2.postid = d.post_id
          and pl2.linktypeid = 3
        order by pl2.creationdate desc
        limit 1
    ) as duplicate_of_title,
    -- string expressions and null logic
    case
        when d.primary_tag is null then '(untagged)'
        when length(d.primary_tag) > 20 then left(d.primary_tag, 20) || '…'
        else d.primary_tag
    end as primary_tag_short,
    -- complicated predicate-driven label
    case
        when coalesce(d.upvotes,0) - coalesce(d.downvotes,0) >= 100 and d.viewcount >= 10000 then 'blockbuster'
        when coalesce(d.upvotes,0) - coalesce(d.downvotes,0) between 20 and 99 then 'popular'
        when coalesce(d.upvotes,0) - coalesce(d.downvotes,0) between 1 and 19 then 'warm'
        when coalesce(d.upvotes,0) - coalesce(d.downvotes,0) = 0 then 'neutral'
        else 'controversial'
    end as popularity_bucket
from dedup d
where d.dedup_rn = 1
order by d.rn_global asc
limit 500;