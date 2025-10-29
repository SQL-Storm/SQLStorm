-- {"query": "5.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2979} 
with recent_posts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.ParentId,
        p.AcceptedAnswerId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.Tags,
        p.Title,
        coalesce(nullif(trim(p.OwnerDisplayName), ''), 'anonymous') as OwnerDisplayNameNorm
    from Posts p
    where p.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts)
),
user_activity as (
    select
        u.Id as UserId,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        u.UpVotes,
        u.DownVotes,
        u.Views,
        count(distinct b.Id) filter (where b.Class = 1) as gold_badges,
        count(distinct b.Id) filter (where b.Class = 2) as silver_badges,
        count(distinct b.Id) filter (where b.Class = 3) as bronze_badges,
        count(distinct b.Id) as total_badges,
        count(distinct c.Id) as comment_count,
        count(distinct v.Id) as vote_events
    from Users u
    left join Badges b on b.UserId = u.Id and b.Date >= u.CreationDate
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.UpVotes, u.DownVotes, u.Views
),
post_votes as (
    select
        v.PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as upvotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as downvotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as favorites,
        sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as bounty_started,
        sum(case when v.VoteTypeId = 9 then coalesce(v.BountyAmount,0) else 0 end) as bounty_awarded,
        min(v.CreationDate) as first_vote_at,
        max(v.CreationDate) as last_vote_at,
        count(*) as total_votes
    from Votes v
    group by v.PostId
),
dup_links as (
    select
        pl.PostId,
        count(*) filter (where pl.LinkTypeId = 3) as duplicate_links,
        count(*) filter (where pl.LinkTypeId = 1) as linked_links,
        min(pl.CreationDate) as first_link_at,
        max(pl.CreationDate) as last_link_at
    from PostLinks pl
    group by pl.PostId
),
close_events as (
    select
        ph.PostId,
        min(ph.CreationDate) filter (where ph.PostHistoryTypeId in (10,35)) as first_close_at,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (10,35)) as last_close_at,
        count(*) filter (where ph.PostHistoryTypeId in (10,35)) as close_events,
        count(*) filter (where ph.PostHistoryTypeId in (11)) as reopen_events,
        sum(
            case
                when ph.PostHistoryTypeId = 10 and ph.Comment ~ '^[0-9]+$'
                    then 1
                when ph.PostHistoryTypeId = 10 and ph.Comment ~ '^(101|102|103|104|105)$'
                    then 1
                else 0
            end
        ) as close_with_reason_events
    from PostHistory ph
    group by ph.PostId
),
tag_explode as (
    select
        rp.Id as PostId,
        lower(trim(t)) as tag
    from recent_posts rp
    cross join lateral unnest(
        case
            when rp.Tags is null then array[]::varchar[]
            else string_to_array(substr(rp.Tags, 2, greatest(length(rp.Tags)-2,0)), '><')
        end
    ) as t
),
tag_stats as (
    select
        te.PostId,
        count(*) as tag_count,
        string_agg(te.tag, ',' order by te.tag) as tag_list_sorted
    from tag_explode te
    group by te.PostId
),
answer_latency as (
    select
        q.Id as QuestionId,
        min(a.CreationDate) as first_answer_at,
        avg(extract(epoch from (a.CreationDate - q.CreationDate))) filter (where a.CreationDate is not null) as avg_answer_latency_sec,
        min(extract(epoch from (a.CreationDate - q.CreationDate))) as min_answer_latency_sec,
        max(extract(epoch from (a.CreationDate - q.CreationDate))) as max_answer_latency_sec,
        count(a.Id) as answer_cnt
    from recent_posts q
    left join Posts a
        on a.ParentId = q.Id
       and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id
),
accepted_answer_age as (
    select
        q.Id as QuestionId,
        q.AcceptedAnswerId,
        a.CreationDate as accepted_created_at,
        extract(epoch from (a.CreationDate - q.CreationDate)) as accepted_latency_sec
    from recent_posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    where q.PostTypeId = 1
),
ranked_users as (
    select
        ua.*,
        row_number() over (order by ua.Reputation desc, ua.total_badges desc, ua.Views desc) as user_rank_global,
        ntile(10) over (order by ua.Reputation desc) as rep_decile
    from user_activity ua
),
post_enriched as (
    select
        rp.*,
        coalesce(pv.upvotes,0) as upvotes,
        coalesce(pv.downvotes,0) as downvotes,
        coalesce(pv.favorites,0) as favorites_votes,
        coalesce(pv.total_votes,0) as total_votes,
        coalesce(pv.first_vote_at, rp.CreationDate) as first_vote_at,
        pv.last_vote_at,
        coalesce(dl.duplicate_links,0) as duplicate_links,
        coalesce(dl.linked_links,0) as linked_links,
        dl.first_link_at,
        dl.last_link_at,
        coalesce(ce.close_events,0) as close_events,
        coalesce(ce.reopen_events,0) as reopen_events,
        ce.first_close_at,
        ce.last_close_at,
        coalesce(ts.tag_count,0) as tag_count,
        ts.tag_list_sorted,
        case when rp.PostTypeId = 1 then al.answer_cnt else null end as answer_cnt,
        case when rp.PostTypeId = 1 then al.first_answer_at else null end as first_answer_at,
        case when rp.PostTypeId = 1 then al.avg_answer_latency_sec else null end as avg_answer_latency_sec,
        case when rp.PostTypeId = 1 then al.min_answer_latency_sec else null end as min_answer_latency_sec,
        case when rp.PostTypeId = 1 then al.max_answer_latency_sec else null end as max_answer_latency_sec,
        case when rp.PostTypeId = 1 then aa.accepted_latency_sec else null end as accepted_latency_sec
    from recent_posts rp
    left join post_votes pv on pv.PostId = rp.Id
    left join dup_links dl on dl.PostId = rp.Id
    left join close_events ce on ce.PostId = rp.Id
    left join tag_stats ts on ts.PostId = rp.Id
    left join answer_latency al on al.QuestionId = rp.Id
    left join accepted_answer_age aa on aa.QuestionId = rp.Id
),
activity_windows as (
    select
        pe.*,
        sum(pe.upvotes - pe.downvotes) over (
            partition by coalesce(pe.OwnerUserId, -1)
            order by pe.CreationDate
            rows between unbounded preceding and current row
        ) as user_net_votes_running,
        avg(pe.Score) over (
            partition by pe.PostTypeId
        ) as avg_score_by_type,
        percentile_cont(0.5) within group (order by coalesce(pe.ViewCount,0))
            over (partition by pe.PostTypeId) as median_views_by_type,
        rank() over (partition by pe.PostTypeId order by coalesce(pe.ViewCount,0) desc) as view_rank_in_type
    from post_enriched pe
),
question_clusters as (
    select
        aw.*,
        case
            when aw.tag_count = 0 then 'untagged'
            when aw.tag_list_sorted like '%sql%' then 'sql'
            when aw.tag_list_sorted like '%python%' then 'python'
            when aw.tag_list_sorted like '%javascript%' then 'javascript'
            else 'other'
        end as topic_bucket
    from activity_windows aw
),
null_edge_cases as (
    select
        qc.*,
        case when qc.OwnerUserId is null and qc.OwnerDisplayNameNorm = 'anonymous' then 1 else 0 end as is_true_anon,
        case when qc.LastActivityDate is null then 1 else 0 end as is_inactive_flag,
        coalesce(qc.ViewCount, 0) as viewcount_nn,
        coalesce(qc.Score, 0) as score_nn
    from question_clusters qc
),
scored as (
    select
        ne.*,
        ru.user_rank_global,
        ru.rep_decile,
        -- composite scoring to benchmark expression complexity
        (
            (coalesce(ne.upvotes,0) * 3 - coalesce(ne.downvotes,0) * 4)
          + (coalesce(ne.favorites_votes,0))
          + (case when ne.PostTypeId = 1 then least(coalesce(ne.answer_cnt,0), 10) * 2 else 0 end)
          + (case when ne.accepted_latency_sec is not null then 15 else 0 end)
          + (case when ne.duplicate_links > 0 then -10 else 0 end)
          + (case when ne.close_events > 0 then -20 else 0 end)
          + (greatest(coalesce(ne.ViewCount,0) - coalesce(ne.median_views_by_type,0), 0) / nullif(ne.median_views_by_type,0))
          + (case when ne.OwnerUserId is null then -5 else 0 end)
        ) as composite_score
    from null_edge_cases ne
    left join ranked_users ru on ru.UserId = ne.OwnerUserId
),
final_rank as (
    select
        s.*,
        dense_rank() over (
            partition by s.PostTypeId, s.topic_bucket
            order by s.composite_score desc nulls last, s.viewcount_nn desc
        ) as dense_rank_in_bucket,
        row_number() over (order by s.composite_score desc nulls last, s.viewcount_nn desc, s.CreationDate desc) as global_rownum
    from scored s
),
correlated_flags as (
    select
        fr.*,
        exists (
            select 1
            from Comments c
            where c.PostId = fr.Id
              and c.Score >= 10
        ) as has_popular_comment,
        exists (
            select 1
            from PostHistory ph
            where ph.PostId = fr.Id
              and ph.PostHistoryTypeId in (24) -- Suggested Edit Applied
        ) as has_suggested_edit,
        (
            select count(*) from Posts a
            where a.ParentId = fr.Id and a.PostTypeId = 2 and a.Score > 0
        ) as positive_answer_count
    from final_rank fr
)
select
    cf.Id as PostId,
    cf.PostTypeId,
    cf.Title,
    cf.OwnerUserId,
    cf.OwnerDisplayNameNorm,
    cf.user_rank_global,
    cf.rep_decile,
    cf.topic_bucket,
    cf.Score,
    cf.ViewCount,
    cf.AnswerCount,
    cf.CommentCount,
    cf.upvotes,
    cf.downvotes,
    cf.favorites_votes,
    cf.duplicate_links,
    cf.close_events,
    cf.reopen_events,
    cf.tag_count,
    cf.tag_list_sorted,
    cf.answer_cnt,
    cf.avg_answer_latency_sec,
    cf.accepted_latency_sec,
    cf.user_net_votes_running,
    cf.avg_score_by_type,
    cf.median_views_by_type,
    cf.view_rank_in_type,
    cf.composite_score,
    cf.dense_rank_in_bucket,
    cf.global_rownum,
    cf.has_popular_comment,
    cf.has_suggested_edit,
    cf.positive_answer_count,
    case
        when cf.PostTypeId = 1 and cf.answer_cnt = 0 and cf.ViewCount > 1000 then 'unanswered-high-view'
        when cf.duplicate_links > 0 then 'duplicate'
        when cf.close_events > 0 and cf.reopen_events = 0 then 'closed'
        when cf.accepted_latency_sec is not null then 'answered-accepted'
        else 'other'
    end as diagnostic_label
from correlated_flags cf
where
    (
        cf.PostTypeId = 1
        and cf.dense_rank_in_bucket <= 50
    )
    or (
        cf.PostTypeId <> 1
        and cf.global_rownum <= 200
    )
order by
    cf.composite_score desc nulls last,
    cf.viewcount_nn desc,
    cf.CreationDate desc;