-- {"query": "4019.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1975} 
with RecursiveUserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        COALESCE(SUM(case when b.Class = 1 then 1 else 0 end), 0) over (partition by u.Id) as GoldBadges,
        COALESCE(SUM(case when b.Class = 2 then 1 else 0 end), 0) over (partition by u.Id) as SilverBadges,
        COALESCE(SUM(case when b.Class = 3 then 1 else 0 end), 0) over (partition by u.Id) as BronzeBadges,
        ROW_NUMBER() over (partition by u.Id order by b.Date desc nulls last) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
),
UserTopBadges as (
    select distinct UserId, DisplayName, GoldBadges, SilverBadges, BronzeBadges
    from RecursiveUserBadgeCounts
    where BadgeRank = 1 or BadgeRank is null
),
UserAnswerStats as (
    select
        p.OwnerUserId as UserId,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        sum(p.Score) filter (where p.PostTypeId = 2) as TotalAnswerScore,
        avg(p.Score) filter (where p.PostTypeId = 2) as AvgAnswerScore,
        max(p.Score) filter (where p.PostTypeId = 2) as MaxAnswerScore,
        count(distinct p.ParentId) filter (where p.PostTypeId = 2) as DistinctQuestionsAnswered
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
UserQuestionCommentStats as (
    select
        p.OwnerUserId as UserId,
        count(distinct p.Id) as QuestionCount,
        sum(p.CommentCount) as TotalQuestionComments,
        avg(p.CommentCount) as AvgCommentsPerQuestion,
        max(p.CommentCount) as MaxQuestionComments
    from Posts p
    where p.PostTypeId = 1 and p.OwnerUserId is not null
    group by p.OwnerUserId
),
UserEngagement as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        us.AnswerCount,
        us.TotalAnswerScore,
        us.AvgAnswerScore,
        us.MaxAnswerScore,
        uq.QuestionCount,
        uq.TotalQuestionComments,
        uq.AvgCommentsPerQuestion,
        uq.MaxQuestionComments,
        b.GoldBadges,
        b.SilverBadges,
        b.BronzeBadges
    from Users u
    left join UserAnswerStats us on u.Id = us.UserId
    left join UserQuestionCommentStats uq on u.Id = uq.UserId
    left join UserTopBadges b on u.Id = b.UserId
),
TopTagsQuestions as (
    select
        t.TagName,
        p.Id as QuestionId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        u.DisplayName as OwnerDisplayName,
        row_number() over (partition by t.TagName order by p.ViewCount desc, p.Score desc nulls last) as TagTopRank
    from Tags t
    join Posts p on p.PostTypeId = 1 and p.Tags like concat('%<', t.TagName, '>%')
    left join Users u on p.OwnerUserId = u.Id
    where t.Count > 1000 -- popular tags only
),
TagTopQuestionsWithAnswers as (
    select
        ttq.TagName,
        ttq.QuestionId,
        ttq.Title,
        ttq.CreationDate,
        ttq.Score,
        ttq.ViewCount,
        ttq.OwnerDisplayName,
        a.Id as AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AcceptedAnswerOwner
    from TopTagsQuestions ttq
    left join Posts a on ttq.QuestionId = a.ParentId and a.Id = (
        select AcceptedAnswerId from Posts where Id = ttq.QuestionId
    )
    where ttq.TagTopRank <= 5
),
DuplicateLinksCTE as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        u.DisplayName as OwnerName,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id and lt.Name = 'Duplicate'
    join Posts p1 on pl.PostId = p1.Id
    join Posts p2 on pl.RelatedPostId = p2.Id
    left join Users u on p1.OwnerUserId = u.Id
),
UserBadgedQuestions as (
    select distinct
        b.UserId,
        p.Id as QuestionId,
        p.Title,
        b.Name as BadgeName,
        b.Class as BadgeClass
    from Badges b
    join Posts p on p.OwnerUserId = b.UserId and p.PostTypeId = 1
    where b.TagBased = 0 and b.Class = 1
),
UserAnswerWithLateEdits as (
    select
        p.Id as AnswerId,
        p.ParentId as QuestionId,
        p.OwnerUserId,
        p.Score,
        ph.CreationDate as LastEditDate,
        row_number() over (partition by p.Id order by ph.CreationDate desc nulls last) as LastEditRank
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId in (5,8) -- edit body or rollback body
    where p.PostTypeId = 2
),
FilteredAnswerLatestEdits as (
    select
        aa.AnswerId,
        aa.QuestionId,
        aa.OwnerUserId,
        aa.Score,
        aa.LastEditDate
    from UserAnswerWithLateEdits aa
    where aa.LastEditRank = 1
),
AnswerScoreWindow as (
    select
        fae.AnswerId,
        fae.QuestionId,
        fae.OwnerUserId,
        fae.Score,
        fae.LastEditDate,
        avg(fae.Score) over (partition by fae.QuestionId) as AvgAnswerScorePerQuestion,
        max(fae.Score) over (partition by fae.QuestionId) as MaxAnswerScorePerQuestion,
        min(fae.Score) over (partition by fae.QuestionId) as MinAnswerScorePerQuestion,
        count(*) over (partition by fae.QuestionId) as TotalAnswersPerQuestion
    from FilteredAnswerLatestEdits fae
)
select
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.Location,
    ue.Views,
    ue.UpVotes,
    ue.DownVotes,
    ue.AnswerCount,
    ue.TotalAnswerScore,
    ue.AvgAnswerScore,
    ue.MaxAnswerScore,
    ue.QuestionCount,
    ue.TotalQuestionComments,
    ue.AvgCommentsPerQuestion,
    ue.MaxQuestionComments,
    ue.GoldBadges,
    ue.SilverBadges,
    ue.BronzeBadges,
    atq.TagName as FavoriteTag,
    atq.QuestionId as PopularQuestionId,
    atq.Title as PopularQuestionTitle,
    atq.ViewCount as PopularQuestionViews,
    atq.Score as PopularQuestionScore,
    dl.PostId as DuplicatePostId,
    dl.RelatedPostId as OriginalPostId,
    dl.PostTitle as DuplicatePostTitle,
    dl.RelatedPostTitle as OriginalPostTitle,
    dl.LinkTypeName as DuplicationType,
    ubq.QuestionId as GoldBadgeQuestionId,
    ubq.Title as GoldBadgeQuestionTitle,
    ubq.BadgeName as GoldBadgeName,
    asw.AnswerId,
    asw.Score as AnswerScore,
    asw.LastEditDate,
    asw.AvgAnswerScorePerQuestion,
    asw.MaxAnswerScorePerQuestion,
    asw.MinAnswerScorePerQuestion,
    asw.TotalAnswersPerQuestion
from UserEngagement ue
left join LATERAL (
    select TagName, QuestionId, Title, ViewCount, Score
    from TopTagsQuestions ttq
    where row_number() over (partition by ttq.TagName order by ttq.ViewCount desc) = 1
      and exists (
        select 1 from Posts p where p.PostTypeId = 1 and p.OwnerUserId = ue.UserId and p.Tags like concat('%<', ttq.TagName, '>%')
      )
    limit 1
) atq on true
left join DuplicateLinksCTE dl on dl.PostId in (
    select Id from Posts p where p.OwnerUserId = ue.UserId and p.PostTypeId in (1,2)
)
left join UserBadgedQuestions ubq on ubq.UserId = ue.UserId
left join AnswerScoreWindow asw on asw.OwnerUserId = ue.UserId
where ue.Reputation > 1000 and (ue.AnswerCount > 10 or ue.QuestionCount > 5)
order by ue.Reputation desc, ue.AnswerCount desc
limit 50;