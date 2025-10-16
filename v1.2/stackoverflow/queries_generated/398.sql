-- {"query": "398.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1978} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        array[t.Id] as AncestorPath
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        t.Id,
        t.TagName,
        t.Count,
        r.AncestorPath || t.Id
    from Tags t
    join RecursiveTagHierarchy r on t.Id = any(r.AncestorPath)
    where t.IsModeratorOnly = 0 and t.IsRequired = 0 and not t.Id = any(r.AncestorPath)
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(ubc_gold.BadgeCount,0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount,0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount,0) as BronzeBadges,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        sum(p.Score) filter (where p.PostTypeId in (1,2)) as TotalPostScore,
        max(p.CreationDate) filter (where p.PostTypeId in (1,2)) as LastPostDate
    from Users u
    left join UserBadgeCounts ubc_gold on ubc_gold.UserId = u.Id and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on ubc_silver.UserId = u.Id and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on ubc_bronze.UserId = u.Id and ubc_bronze.Class = 3
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId in (1,2)
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, ubc_gold.BadgeCount, ubc_silver.BadgeCount, ubc_bronze.BadgeCount
),
PostLinkAggregates as (
    select
        pl.PostId,
        count(distinct case when lt.Name = 'Linked' then pl.RelatedPostId end) as LinkedCount,
        count(distinct case when lt.Name = 'Duplicate' then pl.RelatedPostId end) as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        q.AnswerCount,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreation,
        a.OwnerUserId as AnswerOwnerUserId,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
AnswerWithUser as (
    select
        q.QuestionId,
        q.Title,
        q.QuestionCreation,
        q.QuestionScore,
        q.ViewCount,
        q.Tags,
        q.AnswerCount,
        q.AnswerId,
        q.AnswerScore,
        q.AnswerCreation,
        q.AnswerOwnerUserId,
        u.DisplayName as AnswerOwnerName,
        u.Reputation as AnswerOwnerReputation,
        q.AnswerRank
    from QuestionAnswerStats q
    left join Users u on u.Id = q.AnswerOwnerUserId
),
TopAnswersPerQuestion as (
    select
        QuestionId,
        Title,
        QuestionCreation,
        QuestionScore,
        ViewCount,
        Tags,
        AnswerCount,
        AnswerId,
        AnswerScore,
        AnswerCreation,
        AnswerOwnerUserId,
        AnswerOwnerName,
        AnswerOwnerReputation
    from AnswerWithUser
    where AnswerRank <= 3
),
QuestionsWithLinks as (
    select
        q.QuestionId,
        q.Title,
        q.QuestionCreation,
        q.QuestionScore,
        q.ViewCount,
        q.Tags,
        q.AnswerCount,
        pla.LinkedCount,
        pla.DuplicateCount
    from (
        select distinct QuestionId, Title, QuestionCreation, QuestionScore, ViewCount, Tags, AnswerCount
        from TopAnswersPerQuestion
    ) q
    left join PostLinkAggregates pla on pla.PostId = q.QuestionId
),
RankedUsers as (
    select
        ua.*,
        rank() over (order by ua.Reputation desc, ua.GoldBadges desc, ua.SilverBadges desc, ua.BronzeBadges desc) as UserRank
    from UserActivity ua
),
UserRecentComments as (
    select
        c.UserId,
        count(*) as RecentCommentCount,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    where c.CreationDate > current_date - interval '30 days'
    group by c.UserId
),
UserSummary as (
    select
        ru.UserId,
        ru.DisplayName,
        ru.Reputation,
        ru.GoldBadges,
        ru.SilverBadges,
        ru.BronzeBadges,
        ru.QuestionsCount,
        ru.AnswersCount,
        ru.TotalPostScore,
        ru.LastPostDate,
        coalesce(urc.RecentCommentCount,0) as RecentCommentCount,
        urc.LastCommentDate,
        ru.UserRank
    from RankedUsers ru
    left join UserRecentComments urc on urc.UserId = ru.UserId
),
FinalResults as (
    select
        qwl.QuestionId,
        qwl.Title as QuestionTitle,
        qwl.QuestionCreation,
        qwl.QuestionScore,
        qwl.ViewCount,
        qwl.Tags,
        qwl.AnswerCount,
        qwl.LinkedCount,
        qwl.DuplicateCount,
        ta.AnswerId,
        ta.AnswerScore,
        ta.AnswerCreation,
        ta.AnswerOwnerUserId,
        ta.AnswerOwnerName,
        ta.AnswerOwnerReputation,
        us.UserRank as AnswerOwnerRank,
        us.Reputation as AnswerOwnerReputationTotal,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        us.QuestionsCount,
        us.AnswersCount,
        us.TotalPostScore,
        us.LastPostDate,
        us.RecentCommentCount,
        us.LastCommentDate
    from QuestionsWithLinks qwl
    left join TopAnswersPerQuestion ta on ta.QuestionId = qwl.QuestionId
    left join UserSummary us on us.UserId = ta.AnswerOwnerUserId
    where qwl.QuestionScore > 5 and (qwl.AnswerCount > 0 or qwl.DuplicateCount > 0)
)
select
    fr.QuestionId,
    fr.QuestionTitle,
    fr.QuestionCreation,
    fr.QuestionScore,
    fr.ViewCount,
    fr.Tags,
    fr.AnswerCount,
    fr.LinkedCount,
    fr.DuplicateCount,
    fr.AnswerId,
    fr.AnswerScore,
    fr.AnswerCreation,
    fr.AnswerOwnerUserId,
    coalesce(fr.AnswerOwnerName, 'Unknown') as AnswerOwnerName,
    fr.AnswerOwnerReputation,
    fr.AnswerOwnerRank,
    fr.GoldBadges,
    fr.SilverBadges,
    fr.BronzeBadges,
    fr.QuestionsCount,
    fr.AnswersCount,
    fr.TotalPostScore,
    fr.LastPostDate,
    fr.RecentCommentCount,
    fr.LastCommentDate,
    -- Complex string expression: concatenate tags with user display name and rank
    concat_ws(' | ',
        substring(fr.Tags from 2 for char_length(fr.Tags) - 2),
        'Answerer: ' || coalesce(fr.AnswerOwnerName, 'Unknown'),
        'Rank: ' || coalesce(fr.AnswerOwnerRank::text, 'N/A')
    ) as TagUserRankSummary,
    -- Complex calculation: weighted score combining question and answer scores with badges
    (fr.QuestionScore * 0.6 + coalesce(fr.AnswerScore,0) * 0.4) * 
    (1 + (fr.GoldBadges * 0.05) + (fr.SilverBadges * 0.03) + (fr.BronzeBadges * 0.01)) as WeightedScore,
    -- NULL logic: flag if user has no recent comments
    case when fr.RecentCommentCount is null or fr.RecentCommentCount = 0 then true else false end as NoRecentCommentsFlag
from FinalResults fr
order by WeightedScore desc, fr.QuestionCreation desc
limit 100;