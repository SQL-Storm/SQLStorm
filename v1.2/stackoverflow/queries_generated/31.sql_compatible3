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
    join RecursiveTagHierarchy r on not (t2.Id = any (r.Path))
    where t2.IsRequired = true and t2.Count < r.Count
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
        u.DisplayName as OwnerName,
        dense_rank() over (order by p.Score desc, p.ViewCount desc) as ScoreRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
      and p.CreationDate >= (cast('2024-10-01' as date) - interval '1 year')
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
        count(*) over (
            partition by u.Id
            order by extract(epoch from p.CreationDate)
            range between 30 * 24 * 60 * 60 preceding and current row
        ) as PostsLast30Days,
        sum(p.Score) over (
            partition by u.Id
            order by extract(epoch from p.CreationDate)
            range between 30 * 24 * 60 * 60 preceding and current row
        ) as ScoreLast30Days
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
UserTopTags as (
    select
        p.OwnerUserId as UserId,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as Tag,
        count(*) as TagCount
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
    group by p.OwnerUserId, Tag
),
UserTopTagRanks as (
    select
        ut.UserId,
        ut.Tag,
        ut.TagCount,
        rank() over (partition by ut.UserId order by ut.TagCount desc) as TagRank
    from UserTopTags ut
),
FinalSelection as (
    select
        tq.Id as QuestionId,
        tq.Title,
        tq.OwnerUserId,
        ur.DisplayName as OwnerName,
        ur.Reputation,
        ur.GoldBadges,
        ur.SilverBadges,
        ur.BronzeBadges,
        tq.Score,
        tq.ViewCount,
        tq.AnswerCount,
        coalesce(as_.TotalAnswers, 0) as TotalAnswers,
        coalesce(as_.AvgAnswerScore, 0) as AvgAnswerScore,
        coalesce(as_.MaxAnswerScore, 0) as MaxAnswerScore,
        coalesce(as_.AnsweredByRegisteredUsers, 0) as AnsweredByRegisteredUsers,
        qcr.CloseReasonName,
        qcr.CloseVotesCount,
        ua.PostsLast30Days,
        ua.ScoreLast30Days,
        uttr.Tag as TopTag,
        uttr.TagCount as TopTagCount
    from TopQuestions tq
    left join UserReputationStats ur on ur.UserId = tq.OwnerUserId
    left join AnswerStats as_ on as_.QuestionId = tq.Id
    left join QuestionCloseReasons qcr on qcr.PostId = tq.Id
    left join UserActivityWindow ua on ua.UserId = tq.OwnerUserId and ua.PostId = tq.Id
    left join UserTopTagRanks uttr on uttr.UserId = tq.OwnerUserId and uttr.TagRank = 1
    where tq.ScoreRank <= 100
)
select
    fs.QuestionId,
    fs.Title,
    fs.OwnerName,
    fs.Reputation,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges,
    fs.Score,
    fs.ViewCount,
    fs.AnswerCount,
    fs.TotalAnswers,
    round(cast(fs.AvgAnswerScore as numeric), 2) as AvgAnswerScore,
    fs.MaxAnswerScore,
    fs.AnsweredByRegisteredUsers,
    coalesce(fs.CloseReasonName, 'Open') as CloseReason,
    coalesce(fs.CloseVotesCount, 0) as CloseVotesCount,
    fs.PostsLast30Days,
    fs.ScoreLast30Days,
    fs.TopTag,
    fs.TopTagCount,
    case
        when fs.ViewCount > 10000 then 'High Traffic'
        when fs.ViewCount between 1000 and 10000 then 'Medium Traffic'
        else 'Low Traffic'
    end as TrafficCategory,
    case
        when fs.Reputation >= 100000 then 'Legendary'
        when fs.Reputation >= 10000 then 'Expert'
        when fs.Reputation >= 1000 then 'Intermediate'
        else 'Newbie'
    end as UserLevel,
    concat(
        'Q:', fs.Score, '|A:', fs.TotalAnswers, '|V:', fs.ViewCount, '|G:', fs.GoldBadges, '|S:', fs.SilverBadges, '|B:', fs.BronzeBadges
    ) as SummaryStats
from FinalSelection fs
order by fs.Score desc, fs.ViewCount desc
limit 50;