-- {"query": "261.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2783} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
        sum(coalesce(vu.upvotes, 0)) over () as dummy_window_sum -- provoke global window agg
    from users u
    left join lateral (
        select 1 as upvotes
        where u.upvotes > u.downvotes
    ) vu on true
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
question_basics as (
    select
        p.id as qid,
        p.owneruserid as asker_id,
        p.creationdate as q_created,
        p.score as q_score,
        p.viewcount as q_views,
        p.title,
        p.tags,
        p.acceptedanswerid,
        (string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2, 0)), '><')) as tag_arr
    from posts p
    where p.posttypeid = 1
),
answer_stats as (
    select
        a.parentid as qid,
        count(*) as answer_count,
        max(a.score) as max_answer_score,
        min(a.creationdate) filter (where a.score >= 0) as first_nonneg_ans_date,
        avg(a.score) as avg_answer_score
    from posts a
    where a.posttypeid = 2
    group by a.parentid
),
question_activity as (
    select
        q.qid,
        q.asker_id,
        q.q_created,
        q.q_score,
        q.q_views,
        q.title,
        q.tags,
        q.tag_arr,
        q.acceptedanswerid,
        coalesce(a.answer_count, 0) as answer_count,
        a.max_answer_score,
        a.avg_answer_score,
        a.first_nonneg_ans_date,
        (select count(*) from comments c where c.postid = q.qid) as comment_count,
        (select count(*) from votes v where v.postid = q.qid and v.votetypeid = 2) as upvote_count,
        (select count(*) from votes v where v.postid = q.qid and v.votetypeid = 3) as downvote_count,
        (select count(*) from postlinks pl where pl.postid = q.qid and pl.linktypeid = 3) as duplicate_marks,
        (select count(*) from postlinks pl where pl.relatedpostid = q.qid and pl.linktypeid = 3) as marked_as_original_of_dupe
    from question_basics q
    left join answer_stats a on a.qid = q.qid
),
badge_rollup as (
    select
        b.userid,
        sum(case when b.class = 1 then 1 else 0 end) as golds,
        sum(case when b.class = 2 then 1 else 0 end) as silvers,
        sum(case when b.class = 3 then 1 else 0 end) as bronzes,
        count(*) as total_badges,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
hot_candidates as (
    select
        qa.qid,
        qa.asker_id,
        qa.q_created,
        qa.q_views,
        qa.q_score,
        qa.answer_count,
        qa.upvote_count,
        qa.downvote_count,
        qa.duplicate_marks,
        qa.marked_as_original_of_dupe,
        qa.comment_count,
        qa.title,
        qa.tags,
        qa.tag_arr,
        qa.acceptedanswerid,
        qa.max_answer_score,
        qa.avg_answer_score,
        qa.first_nonneg_ans_date,
        -- synthetic engagement score
        (qa.q_score * 3
         + coalesce(qa.upvote_count, 0) * 2
         - coalesce(qa.downvote_count, 0) * 2
         + coalesce(qa.answer_count, 0) * 4
         + least(coalesce(qa.comment_count, 0), 20)
         + ln(greatest(qa.q_views + 1, 1))
        )::numeric as engagement_score
    from question_activity qa
    where qa.q_created >= (select max(q_created) - interval '90 days' from question_activity)
),
tag_expansion as (
    select
        hc.qid,
        unnest(hc.tag_arr) as tagname,
        hc.engagement_score,
        hc.asker_id,
        hc.q_created,
        hc.q_views,
        hc.q_score,
        hc.answer_count,
        hc.title
    from hot_candidates hc
),
tag_stats as (
    select
        te.qid,
        te.tagname,
        te.engagement_score,
        row_number() over (partition by te.qid order by ts.count desc nulls last, te.tagname) as tag_rank_by_pop,
        ts.count as tag_global_count
    from tag_expansion te
    left join tags ts on lower(ts.tagname) = lower(te.tagname)
),
asker_quality as (
    select
        u.id as user_id,
        coalesce(u.reputation, 0) as reputation,
        coalesce(br.total_badges, 0) as total_badges,
        coalesce(br.golds, 0) as golds,
        coalesce(br.silvers, 0) as silvers,
        coalesce(br.bronzes, 0) as bronzes,
        coalesce(u.upvotes, 0) - coalesce(u.downvotes, 0) as net_votes,
        width_bucket(coalesce(u.reputation, 0), 0, 100000, 10) as rep_bucket
    from users u
    left join badge_rollup br on br.userid = u.id
),
post_history_flags as (
    select
        ph.postid,
        max(case when ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35) then 1 else 0 end) as has_moderation_event,
        max(case when ph.posthistorytypeid = 50 then 1 else 0 end) as was_community_bumped,
        max(case when ph.posthistorytypeid in (52,53) then 1 else 0 end) as in_hot_network_once,
        count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edit_events,
        min(ph.creationdate) filter (where ph.posthistorytypeid in (10)) as first_close_vote_date
    from posthistory ph
    group by ph.postid
),
dupe_rels as (
    select
        pl.postid as dupe_post_id,
        pl.relatedpostid as original_post_id,
        pl.creationdate as dupe_date
    from postlinks pl
    where pl.linktypeid = 3
),
agg as (
    select
        hc.qid,
        hc.title,
        hc.tags,
        u.displayname as asker,
        aq.reputation,
        aq.total_badges,
        aq.golds,
        aq.silvers,
        aq.bronzes,
        aq.net_votes,
        aq.rep_bucket,
        hc.q_created,
        hc.q_views,
        hc.q_score,
        hc.answer_count,
        hc.engagement_score,
        ts.tagname as top_tag,
        ts.tag_global_count,
        phf.has_moderation_event,
        phf.was_community_bumped,
        phf.in_hot_network_once,
        phf.edit_events,
        phf.first_close_vote_date,
        case
            when hc.acceptedanswerid is null and hc.answer_count > 0 then 'unaccepted'
            when hc.acceptedanswerid is not null then 'accepted'
            else 'unanswered'
        end as answer_state,
        case
            when exists (
                select 1 from dupe_rels d where d.dupe_post_id = hc.qid
            ) then 'duplicate'
            when exists (
                select 1 from dupe_rels d where d.original_post_id = hc.qid
            ) then 'dupe-target'
            else 'unique'
        end as dupe_status
    from hot_candidates hc
    left join tag_stats ts
        on ts.qid = hc.qid
       and ts.tag_rank_by_pop = 1
    left join post_history_flags phf
        on phf.postid = hc.qid
    left join users u
        on u.id = hc.asker_id
    left join asker_quality aq
        on aq.user_id = hc.asker_id
),
ranked as (
    select
        a.*,
        row_number() over (
            partition by coalesce(a.top_tag, 'unknown')
            order by
                a.engagement_score desc nulls last,
                a.q_views desc nulls last,
                a.q_created desc
        ) as rn_by_tag,
        dense_rank() over (
            order by
                (a.engagement_score
                 + case when a.has_moderation_event = 1 then -5 else 0 end
                 + case when a.was_community_bumped = 1 then -3 else 0 end
                 + case when a.in_hot_network_once = 1 then 2 else 0 end
                ) desc nulls last
        ) as overall_rank
    from agg a
),
bucketed as (
    select
        r.*,
        case
            when r.engagement_score is null then 'Z-unknown'
            when r.engagement_score >= 200 then 'A-elite'
            when r.engagement_score >= 100 then 'B-high'
            when r.engagement_score >= 50 then 'C-mid'
            when r.engagement_score >= 20 then 'D-low'
            else 'E-very-low'
        end as engagement_bucket
    from ranked r
),
filtered as (
    select *
    from bucketed b
    where
        -- exclude clearly noisy/edge cases via complicated predicate
        not (
            coalesce(b.has_moderation_event, 0) = 1
            and coalesce(b.in_hot_network_once, 0) = 0
            and b.answer_state = 'unanswered'
            and coalesce(b.tag_global_count, 0) < 5
        )
        and (b.q_views > 0 or b.q_score > 0 or b.answer_count > 0)
        and (b.dupe_status <> 'duplicate' or b.engagement_score >= 75)
)
select
    f.overall_rank,
    f.rn_by_tag as rank_within_tag,
    f.engagement_bucket,
    coalesce(f.top_tag, 'unknown') as top_tag,
    f.qid,
    left(coalesce(f.title, ''), 120) as title_prefix,
    f.tags,
    coalesce(f.asker, '[unknown]') as asker,
    f.reputation,
    f.total_badges,
    f.net_votes,
    f.q_created,
    f.q_views,
    f.q_score,
    f.answer_count,
    round(coalesce(f.engagement_score, 0), 2) as engagement_score,
    f.answer_state,
    f.dupe_status,
    f.has_moderation_event,
    f.was_community_bumped,
    f.in_hot_network_once,
    f.edit_events,
    case
        when f.first_close_vote_date is null then null
        else f.q_created + (f.first_close_vote_date - f.q_created)
    end as time_to_first_close_vote,
    -- string and null logic demonstration
    trim(both ' ' from coalesce(regexp_replace(f.tags, '[^a-zA-Z0-9<>-]', '', 'g'), '')) as sanitized_tags,
    -- correlated scalar subquery to get accepted answer score if present
    (
        select p2.score
        from posts p2
        where p2.id = (
            select p.acceptedanswerid
            from posts p
            where p.id = f.qid
        )
    ) as accepted_answer_score,
    -- set operator intersection size: number of tags that are among global top 50 by Count
    (
        select count(*)
        from (
            select lower(tn) as tn
            from unnest(string_to_array(substring(coalesce(f.tags, ''), 2, greatest(length(coalesce(f.tags, ''))-2, 0)), '><')) as tn
            intersect
            select lower(t.tagname)
            from (
                select tagname
                from tags
                order by count desc nulls last
                limit 50
            ) t
        ) s
    ) as n_tags_in_top50
from filtered f
qualify f.overall_rank <= 200 or (f.engagement_bucket in ('A-elite','B-high') and f.rn_by_tag <= 10)
order by f.overall_rank, f.rn_by_tag, f.qid;