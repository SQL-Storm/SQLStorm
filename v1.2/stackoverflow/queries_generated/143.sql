-- {"query": "143.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2129} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0

    union all

    select
        t.Id,
        t.TagName,
        t.Count,
        r.Level + 1,
        r.Path || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> r.Id and not t.TagName = any(r.Path)
    where t.IsModeratorOnly = 0 and t.IsRequired = 0 and r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationRanks as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        dense_rank() over (order by u.Reputation desc) as ReputationRank,
        row_number() over (partition by u.Location order by u.Reputation desc) as LocationRepRank
    from Users u
    where u.Reputation is not null
),
PostAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        count(a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.OwnerUserId is not null then 1 else 0 end) as AnsweredByRegisteredUsers
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.Tags
),
PostCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    where ph.PostHistoryTypeId = 10
),
TopUsersWithBadges as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(ubc_gold.BadgeCount, 0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount, 0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount, 0) as BronzeBadges,
        (coalesce(ubc_gold.BadgeCount, 0) * 3 + coalesce(ubc_silver.BadgeCount, 0) * 2 + coalesce(ubc_bronze.BadgeCount, 0)) as BadgeScore
    from Users u
    left join UserBadgeCounts ubc_gold on ubc_gold.UserId = u.Id and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on ubc_silver.UserId = u.Id and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on ubc_bronze.UserId = u.Id and ubc_bronze.Class = 3
    where u.Reputation > 1000
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesGiven,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesGiven,
        max(p.CreationDate) as LastPostDate,
        max(c.CreationDate) as LastCommentDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),
QuestionsWithDuplicateLinks as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score,
        count(distinct pl.Id) as DuplicateCount,
        string_agg(distinct pl.RelatedPostId::text, ',') as DuplicatePostIds
    from Posts q
    left join PostLinks pl on pl.PostId = q.Id and pl.LinkTypeId = 3
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.Score
),
QuestionsWithAcceptedAnswerDetails as (
    select
        q.Id as QuestionId,
        q.Title,
        q.AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AcceptedAnswerOwner,
        u.DisplayName as AcceptedAnswerOwnerName,
        a.CreationDate as AcceptedAnswerCreationDate
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
QuestionsWithCloseInfo as (
    select
        q.Id as QuestionId,
        q.Title,
        pcr.CloseReasonName,
        pcr.CloseDate
    from Posts q
    left join PostCloseReasons pcr on pcr.PostId = q.Id
    where q.PostTypeId = 1
),
FinalQuestionStats as (
    select
        pas.QuestionId,
        pas.Title,
        pas.QuestionCreation,
        pas.QuestionScore,
        pas.ViewCount,
        pas.Tags,
        pas.AnswerCount,
        pas.MaxAnswerScore,
        pas.AvgAnswerScore,
        pas.AnsweredByRegisteredUsers,
        qad.AcceptedAnswerId,
        qad.AcceptedAnswerScore,
        qad.AcceptedAnswerOwner,
        qad.AcceptedAnswerOwnerName,
        qad.AcceptedAnswerCreationDate,
        qdl.DuplicateCount,
        qdl.DuplicatePostIds,
        qci.CloseReasonName,
        qci.CloseDate
    from PostAnswerStats pas
    left join QuestionsWithAcceptedAnswerDetails qad on qad.QuestionId = pas.QuestionId
    left join QuestionsWithDuplicateLinks qdl on qdl.QuestionId = pas.QuestionId
    left join QuestionsWithCloseInfo qci on qci.QuestionId = pas.QuestionId
),
RankedQuestions as (
    select
        *,
        row_number() over (partition by CloseReasonName order by QuestionScore desc nulls last, ViewCount desc nulls last) as RankWithinCloseReason,
        rank() over (order by AnswerCount desc nulls last, AvgAnswerScore desc nulls last) as OverallAnswerRank
    from FinalQuestionStats
    where CloseReasonName is not null
),
FilteredQuestions as (
    select *
    from RankedQuestions
    where RankWithinCloseReason <= 5 or OverallAnswerRank <= 10
),
UserRecentActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        max(p.CreationDate) as LastPostDate,
        max(c.CreationDate) as LastCommentDate,
        max(v.CreationDate) as LastVoteDate,
        greatest(
            coalesce(max(p.CreationDate), '1900-01-01'::timestamp),
            coalesce(max(c.CreationDate), '1900-01-01'::timestamp),
            coalesce(max(v.CreationDate), '1900-01-01'::timestamp)
        ) as LastActivityDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
)
select
    fq.QuestionId,
    fq.Title,
    fq.QuestionCreation,
    fq.QuestionScore,
    fq.ViewCount,
    fq.Tags,
    fq.AnswerCount,
    fq.MaxAnswerScore,
    round(fq.AvgAnswerScore::numeric, 2) as AvgAnswerScore,
    fq.AnsweredByRegisteredUsers,
    fq.AcceptedAnswerId,
    fq.AcceptedAnswerScore,
    fq.AcceptedAnswerOwner,
    fq.AcceptedAnswerOwnerName,
    fq.AcceptedAnswerCreationDate,
    fq.DuplicateCount,
    fq.DuplicatePostIds,
    fq.CloseReasonName,
    fq.CloseDate,
    ru.DisplayName as RecentActiveUser,
    ru.LastActivityDate,
    tgh.Level as TagHierarchyLevel,
    array_to_string(tgh.Path, ' > ') as TagHierarchyPath,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    tu.BadgeScore,
    ua.QuestionsPosted,
    ua.AnswersPosted,
    ua.CommentsMade,
    ua.UpVotesGiven,
    ua.DownVotesGiven
from FilteredQuestions fq
left join LATERAL (
    select u.Id, u.DisplayName, ua.LastActivityDate
    from Users u
    join UserRecentActivity ua on ua.UserId = u.Id
    where u.Id = fq.AcceptedAnswerOwner
    limit 1
) ru on true
left join RecursiveTagHierarchy tgh on tgh.TagName = split_part(fq.Tags, '><', 1)
left join TopUsersWithBadges tu on tu.Id = fq.AcceptedAnswerOwner
left join UserActivitySummary ua on ua.UserId = fq.AcceptedAnswerOwner
order by fq.QuestionScore desc nulls last, fq.ViewCount desc nulls last, fq.QuestionCreation desc
limit 50;