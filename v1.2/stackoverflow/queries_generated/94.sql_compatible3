with recursive RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        1 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsRequired = true

    union all

    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        t2.IsModeratorOnly,
        t2.IsRequired,
        r.Level + 1,
        r.Path || t2.Id
    from Tags t2
    join RecursiveTagHierarchy r on t2.IsRequired = true and not t2.Id = any(r.Path)
    where r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        coalesce(ubc_gold.BadgeCount, 0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount, 0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount, 0) as BronzeBadges,
        row_number() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join UserBadgeCounts ubc_gold on ubc_gold.UserId = u.Id and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on ubc_silver.UserId = u.Id and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on ubc_bronze.UserId = u.Id and ubc_bronze.Class = 3
),
TopQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        u.DisplayName as OwnerDisplayName,
        dense_rank() over (order by p.Score desc, p.ViewCount desc) as ScoreRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
      and p.CreationDate >= cast('2024-10-01' as date) - interval '1 year'
      and p.ClosedDate is null
),
AnswerStats as (
    select
        a.ParentId as QuestionId,
        count(*) as TotalAnswers,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.OwnerUserId is null then 0 else 1 end) as AnsweredByRegisteredUsers
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        count(*) as CloseVotesCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        -- Use RANGE with numeric second interval is not portable; replace with ROWS-based window over a generated date bucket
        -- Compute counts/sums for posts within 30 days via lateral aggregation per user and post
        -- We'll compute windowed values using a correlated subquery for portability
        null::integer as PostsLast30Days,
        null::bigint as ScoreLast30Days
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
UserActivityWindowCounts as (
    select
        ua.UserId,
        ua.PostId,
        ua.PostTypeId,
        ua.Score,
        ua.CreationDate,
        (
            select count(*)
            from Posts p2
            where p2.OwnerUserId = ua.UserId
              and p2.CreationDate between ua.CreationDate - interval '30 days' and ua.CreationDate
        ) as PostsLast30Days,
        (
            select coalesce(sum(p2.Score),0)
            from Posts p2
            where p2.OwnerUserId = ua.UserId
              and p2.CreationDate between ua.CreationDate - interval '30 days' and ua.CreationDate
        ) as ScoreLast30Days
    from UserActivityWindow ua
),
UserCommentStats as (
    select
        c.UserId,
        count(*) as TotalComments,
        avg(length(c.Text)) as AvgCommentLength,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.UserId
),
CombinedUserStats as (
    select
        urs.UserId,
        urs.DisplayName,
        urs.Reputation,
        urs.Location,
        urs.GoldBadges,
        urs.SilverBadges,
        urs.BronzeBadges,
        ua.PostsLast30Days,
        ua.ScoreLast30Days,
        coalesce(ucs.TotalComments, 0) as TotalComments,
        coalesce(ucs.AvgCommentLength, 0) as AvgCommentLength,
        coalesce(ucs.LastCommentDate, null) as LastCommentDate
    from UserReputationStats urs
    left join (
        -- pick the latest activity row per user to represent the 30-day window aggregates
        select distinct on (UserId) UserId, PostsLast30Days, ScoreLast30Days
        from UserActivityWindowCounts
        order by UserId, CreationDate desc NULLS LAST
    ) ua on ua.UserId = urs.UserId
    left join UserCommentStats ucs on ucs.UserId = urs.UserId
    where ua.PostsLast30Days is not null
),
HighImpactQuestions as (
    select
        tq.Id,
        tq.Title,
        tq.OwnerUserId,
        tq.Score,
        tq.ViewCount,
        tq.AnswerCount,
        tq.FavoriteCount,
        tq.Tags,
        as1.TotalAnswers,
        as1.AvgAnswerScore,
        as1.MaxAnswerScore,
        as1.AnsweredByRegisteredUsers,
        qcr.CloseReasonName,
        qcr.CloseVotesCount
    from TopQuestions tq
    left join AnswerStats as1 on as1.QuestionId = tq.Id
    left join QuestionCloseReasons qcr on qcr.PostId = tq.Id
    where tq.ScoreRank <= 100
),
FinalResult as (
    select
        hiq.Id as QuestionId,
        hiq.Title,
        hiq.OwnerUserId,
        urs.DisplayName as OwnerName,
        urs.Reputation as OwnerReputation,
        hiq.Score as QuestionScore,
        hiq.ViewCount,
        hiq.AnswerCount,
        hiq.FavoriteCount,
        hiq.TotalAnswers,
        round(cast(hiq.AvgAnswerScore as numeric), 2) as AvgAnswerScore,
        hiq.MaxAnswerScore,
        hiq.AnsweredByRegisteredUsers,
        hiq.CloseReasonName,
        hiq.CloseVotesCount,
        urs.GoldBadges,
        urs.SilverBadges,
        urs.BronzeBadges,
        urs.TotalComments,
        urs.AvgCommentLength,
        urs.LastCommentDate,
        string_agg(distinct rth.TagName, ', ') as RequiredTags
    from HighImpactQuestions hiq
    left join CombinedUserStats urs on urs.UserId = hiq.OwnerUserId
    left join RecursiveTagHierarchy rth on position('<' || rth.TagName || '>' in coalesce(hiq.Tags, '')) > 0
    group by
        hiq.Id, hiq.Title, hiq.OwnerUserId, urs.DisplayName, urs.Reputation,
        hiq.Score, hiq.ViewCount, hiq.AnswerCount, hiq.FavoriteCount,
        hiq.TotalAnswers, hiq.AvgAnswerScore, hiq.MaxAnswerScore, hiq.AnsweredByRegisteredUsers,
        hiq.CloseReasonName, hiq.CloseVotesCount,
        urs.GoldBadges, urs.SilverBadges, urs.BronzeBadges,
        urs.TotalComments, urs.AvgCommentLength, urs.LastCommentDate
)
select *
from FinalResult
order by QuestionScore desc, ViewCount desc
limit 50;