-- {"query": "985.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3456}
with recent_questions as (
    select
        p.Id as QuestionId,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        coalesce(p.AnswerCount, 0) as AnswerCount
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts where PostTypeId = 1)
),
user_activity as (
    select
        u.Id as UserId,
        u.Reputation,
        u.CreationDate as UserCreated,
        u.Location,
        u.DisplayName,
        u.UpVotes,
        u.DownVotes,
        u.Views as ProfileViews,
        coalesce(b.badge_count, 0) as BadgeCount
    from Users u
    left join (
        select UserId, count(*) as badge_count
        from Badges
        group by UserId
    ) b on b.UserId = u.Id
),
answers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc, a.Id asc) as rn_by_score,
        min(a.CreationDate) over (partition by a.ParentId) as FirstAnswerAt
    from Posts a
    where a.PostTypeId = 2
),
accepted as (
    select
        q.Id as QuestionId,
        q.AcceptedAnswerId
    from Posts q
    where q.PostTypeId = 1
      and q.AcceptedAnswerId is not null
),
dup_links as (
    select
        pl.PostId as QuestionId,
        count(*) filter (where pl.LinkTypeId = 3) as DuplicateCount,
        count(*) filter (where pl.LinkTypeId = 1) as LinkedCount,
        max(pl.CreationDate) as LastLinkDate
    from PostLinks pl
    group by pl.PostId
),
edits as (
    select
        ph.PostId as QuestionId,
        count(*) filter (where ph.PostHistoryTypeId in (4,5,6,7,8,9,24)) as EditCount,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6,24)) as LastEditDate,
        count(*) filter (where ph.PostHistoryTypeId in (10,11)) as CloseReopenEvents,
        sum(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as CloseEvents,
        sum(case when ph.PostHistoryTypeId = 11 then 1 else 0 end) as ReopenEvents,
        count(*) filter (where ph.PostHistoryTypeId in (35,36)) as MigrationEvents
    from PostHistory ph
    group by ph.PostId
),
vote_agg as (
    select
        v.PostId,
        count(*) filter (where v.VoteTypeId = 2) as UpVotes,
        count(*) filter (where v.VoteTypeId = 3) as DownVotes,
        count(*) filter (where v.VoteTypeId = 5) as Favorites,
        count(*) filter (where v.VoteTypeId in (8,9)) as BountyEvents,
        sum(case when v.VoteTypeId = 9 then coalesce(v.BountyAmount,0) else 0 end) as BountyAwarded
    from Votes v
    group by v.PostId
),
comment_agg as (
    select
        c.PostId,
        count(*) as CommentCount,
        max(c.Score) as MaxCommentScore,
        max(c.CreationDate) as LastCommentDate,
        avg(nullif(c.Score,0)) as AvgNonZeroCommentScore
    from Comments c
    group by c.PostId
),
tag_unpivot as (
    select
        q.QuestionId,
        unnest(string_to_array(substring(q.Tags, 2, greatest(length(q.Tags)-2,0)), '><')) as tag
    from recent_questions q
    where q.Tags is not null and length(q.Tags) >= 2
),
tag_rank as (
    select
        QuestionId,
        tag,
        row_number() over (partition by QuestionId order by coalesce(t.Count,0) desc, tag asc) as tag_pop_rank,
        coalesce(t.Count,0) as GlobalTagCount
    from tag_unpivot tu
    left join Tags t on lower(t.TagName) = lower(tu.tag)
),
question_windows as (
    select
        rq.*,
        ntile(10) over (order by coalesce(rq.ViewCount,0) desc) as view_ntile_10,
        rank() over (order by coalesce(rq.Score,0) desc, coalesce(rq.ViewCount,0) desc) as global_rank_by_score_views,
        avg(coalesce(rq.Score,0)) over () as avg_score_all_recent
    from recent_questions rq
),
first_answer as (
    select
        a.QuestionId,
        min(a.AnswerCreationDate) as FirstAnswerAt
    from answers a
    group by a.QuestionId
),
best_answer as (
    select
        a.QuestionId,
        a.AnswerId,
        a.OwnerUserId as BestAnswerOwnerId,
        a.AnswerScore
    from answers a
    where a.rn_by_score = 1
),
accepted_flag as (
    select
        rq.QuestionId,
        case when ac.AcceptedAnswerId is not null then 1 else 0 end as HasAccepted,
        ac.AcceptedAnswerId
    from recent_questions rq
    left join accepted ac on ac.QuestionId = rq.QuestionId
),
owner_stats as (
    select
        rq.QuestionId,
        ua.UserId,
        ua.Reputation,
        ua.BadgeCount,
        ua.UpVotes,
        ua.DownVotes,
        ua.ProfileViews,
        extract(epoch from age(rq.CreationDate, ua.UserCreated)) as UserAgeSecondsAtPost
    from recent_questions rq
    left join user_activity ua on ua.UserId = rq.OwnerUserId
),
score_buckets as (
    select
        rq.QuestionId,
        case
            when rq.Score is null then 'unknown'
            when rq.Score >= 50 then '50+'
            when rq.Score >= 20 then '20-49'
            when rq.Score >= 10 then '10-19'
            when rq.Score >= 0 then '0-9'
            when rq.Score >= -5 then '-5 - -1'
            else '< -5'
        end as score_bucket
    from recent_questions rq
),
closed_reasons as (
    select
        ph.PostId as QuestionId,
        max(case when ph.PostHistoryTypeId = 10 then ph.Comment end) as LastCloseReasonIdText,
        bool_or(ph.PostHistoryTypeId = 10) as WasClosed
    from PostHistory ph
    group by ph.PostId
),
q_with_votes_comments as (
    select
        rq.QuestionId,
        coalesce(va.UpVotes,0) as UpVotes,
        coalesce(va.DownVotes,0) as DownVotes,
        coalesce(va.Favorites,0) as Favorites,
        coalesce(va.BountyEvents,0) as BountyEvents,
        coalesce(va.BountyAwarded,0) as BountyAwarded,
        coalesce(ca.CommentCount,0) as CommentCount,
        ca.MaxCommentScore,
        ca.LastCommentDate,
        ca.AvgNonZeroCommentScore
    from recent_questions rq
    left join vote_agg va on va.PostId = rq.QuestionId
    left join comment_agg ca on ca.PostId = rq.QuestionId
),
q_scored as (
    select
        qw.QuestionId,
        qw.Score,
        qw.ViewCount,
        qw.AnswerCount,
        qw.CreationDate,
        qw.Title,
        qw.Tags,
        qw.view_ntile_10,
        qw.global_rank_by_score_views,
        (
            coalesce(qwv.UpVotes,0) * 3
            - coalesce(qwv.DownVotes,0) * 2
            + coalesce(qwv.Favorites,0)
            + least(coalesce(qwv.CommentCount,0), 50)
            + coalesce(qwv.BountyEvents,0) * 5
            + case when af.HasAccepted = 1 then 10 else 0 end
            + case when ed.EditCount > 0 then 1 else 0 end
            + case when dl.DuplicateCount > 0 then -10 else 0 end
        ) as EngagementScore,
        qwv.UpVotes, qwv.DownVotes, qwv.Favorites, qwv.BountyEvents, qwv.BountyAwarded, qwv.CommentCount, qwv.MaxCommentScore, qwv.LastCommentDate, qwv.AvgNonZeroCommentScore,
        ed.EditCount, ed.LastEditDate, ed.CloseReopenEvents, ed.CloseEvents, ed.ReopenEvents, ed.MigrationEvents,
        dl.DuplicateCount, dl.LinkedCount, dl.LastLinkDate,
        af.HasAccepted, af.AcceptedAnswerId
    from question_windows qw
    left join q_with_votes_comments qwv on qwv.QuestionId = qw.QuestionId
    left join edits ed on ed.QuestionId = qw.QuestionId
    left join dup_links dl on dl.QuestionId = qw.QuestionId
    left join accepted_flag af on af.QuestionId = qw.QuestionId
),
final as (
    select
        qs.QuestionId,
        qs.Title,
        qs.Score,
        qs.ViewCount,
        qs.AnswerCount,
        qs.CreationDate,
        os.UserId as OwnerUserId,
        os.Reputation as OwnerReputation,
        os.BadgeCount as OwnerBadges,
        os.UpVotes as OwnerUpVotes,
        os.DownVotes as OwnerDownVotes,
        os.ProfileViews as OwnerProfileViews,
        os.UserAgeSecondsAtPost,
        af.HasAccepted,
        qs.AcceptedAnswerId,
        ba.AnswerId as BestAnswerId,
        ba.BestAnswerOwnerId,
        ba.AnswerScore as BestAnswerScore,
        fa.FirstAnswerAt,
        extract(epoch from (fa.FirstAnswerAt - qs.CreationDate)) as TimeToFirstAnswerSeconds,
        extract(epoch from (qs.LastEditDate - qs.CreationDate)) as TimeToFirstEditSeconds,
        qs.EditCount, qs.LastEditDate, qs.CloseReopenEvents, qs.CloseEvents, qs.ReopenEvents, qs.MigrationEvents,
        qs.DuplicateCount, qs.LinkedCount, qs.LastLinkDate,
        qs.UpVotes, qs.DownVotes, qs.Favorites, qs.BountyEvents, qs.BountyAwarded,
        qs.CommentCount, qs.MaxCommentScore, qs.LastCommentDate, qs.AvgNonZeroCommentScore,
        qs.EngagementScore,
        sr.score_bucket,
        cr.WasClosed,
        cr.LastCloseReasonIdText,
        (qs.Score >= 10 and qs.ViewCount >= 1000) as IsPopular,
        (qs.Score < 0 or qs.DownVotes > qs.UpVotes) as IsControversial,
        (qs.DuplicateCount > 0 and coalesce(qs.LinkedCount,0) = 0) as IsLikelyDuplicateOnly,
        max(case when tr.tag_pop_rank = 1 then tr.tag end) as TopTag,
        max(case when tr.tag_pop_rank = 1 then tr.GlobalTagCount end) as TopTagGlobalCount,
        coalesce(nullif(trim(qs.Tags), ''), '[no-tags]') as NormalizedTags,
        substring(coalesce(qs.Title,''), 1, 100) as TitleSample,
        length(coalesce(qs.Title,'')) as TitleLength
    from q_scored qs
    left join owner_stats os on os.QuestionId = qs.QuestionId
    left join accepted_flag af on af.QuestionId = qs.QuestionId
    left join best_answer ba on ba.QuestionId = qs.QuestionId
    left join first_answer fa on fa.QuestionId = qs.QuestionId
    left join score_buckets sr on sr.QuestionId = qs.QuestionId
    left join closed_reasons cr on cr.QuestionId = qs.QuestionId
    left join tag_rank tr on tr.QuestionId = qs.QuestionId
    group by
        qs.QuestionId, qs.Title, qs.Score, qs.ViewCount, qs.AnswerCount, qs.CreationDate,
        os.UserId, os.Reputation, os.BadgeCount, os.UpVotes, os.DownVotes, os.ProfileViews, os.UserAgeSecondsAtPost,
        af.HasAccepted, qs.AcceptedAnswerId, ba.AnswerId, ba.BestAnswerOwnerId, ba.AnswerScore,
        fa.FirstAnswerAt, qs.LastEditDate, qs.EditCount, qs.CloseReopenEvents, qs.CloseEvents, qs.ReopenEvents, qs.MigrationEvents,
        qs.DuplicateCount, qs.LinkedCount, qs.LastLinkDate, qs.UpVotes, qs.DownVotes, qs.Favorites, qs.BountyEvents, qs.BountyAwarded,
        qs.CommentCount, qs.MaxCommentScore, qs.LastCommentDate, qs.AvgNonZeroCommentScore,
        qs.EngagementScore, sr.score_bucket, cr.WasClosed, cr.LastCloseReasonIdText, qs.Tags
),
ranked as (
    select
        f.*,
        dense_rank() over (order by
            f.EngagementScore desc,
            coalesce(f.ViewCount,0) desc,
            coalesce(f.Score,0) desc,
            f.CreationDate desc,
            f.QuestionId desc
        ) as DenseRankEngagement,
        percent_rank() over (order by coalesce(f.ViewCount,0)) as ViewPercentRank,
        cume_dist() over (order by coalesce(f.Score,0) desc) as ScoreCumeDist
    from final f
),
unioned as (
    select * from ranked where IsPopular
    union
    select * from ranked where not IsPopular
)
select
    u.*,
    (
        select count(1)
        from Comments c
        where c.PostId = u.QuestionId
          and c.Score > coalesce(u.MaxCommentScore, -1000)
    ) as CommentsAboveMaxScore,
    (
        select count(1)
        from Votes v
        where v.PostId = u.QuestionId
          and v.VoteTypeId = 2
          and v.CreationDate >= u.CreationDate
    ) as UpvotesAfterPostCreation,
    case
        when u.HasAccepted = 1 and u.BestAnswerId is null then 1
        when u.HasAccepted = 0 and u.BestAnswerId is not null then 2
        when u.HasAccepted = 1 and u.BestAnswerId is not null then 3
        else 0
    end as AcceptanceStateCode
from unioned u
where
    (
        (u.EngagementScore >= 5 and coalesce(u.ViewCount,0) > 100)
        or (u.IsControversial and coalesce(u.DownVotes,0) >= 5)
        or (u.IsLikelyDuplicateOnly and u.Score <= 0)
    )
    and coalesce(u.TitleLength,0) > 0
    and (
        u.TopTag is null
        or (
            lower(u.TopTag) not like '%test%' 
            and lower(u.TopTag) not like '%hello%' 
            and lower(u.TopTag) not like '%misc%'
        )
    )
order by
    u.DenseRankEngagement,
    u.ViewPercentRank,
    u.ScoreCumeDist desc,
    u.QuestionId
limit 500;