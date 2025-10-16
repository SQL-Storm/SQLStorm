-- {"query": "120.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1365} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
        coalesce(sum(v.BountyAmount),0) as TotalBountyGiven,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join Votes v on v.UserId = u.Id and v.BountyAmount is not null
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        p.AcceptedAnswerId,
        u.DisplayName as OwnerName,
        dense_rank() over (order by p.Score desc, p.ViewCount desc) as ScoreRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
),
AcceptedAnswerDetails as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        u.DisplayName as AnswerOwnerName,
        (select count(*) from Comments c where c.PostId = a.Id) as AnswerCommentCount
    from Posts a
    left join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
),
QuestionAnswerStats as (
    select
        tq.Id as QuestionId,
        tq.Title,
        tq.OwnerUserId,
        tq.OwnerName,
        tq.Score as QuestionScore,
        tq.ViewCount,
        tq.CreationDate as QuestionCreationDate,
        tq.Tags,
        coalesce(a.AnswerScore, 0) as AcceptedAnswerScore,
        coalesce(a.AnswerOwnerName, 'N/A') as AcceptedAnswerOwner,
        coalesce(a.AnswerCommentCount, 0) as AcceptedAnswerComments,
        (select count(*) from Posts p2 where p2.ParentId = tq.Id and p2.PostTypeId = 2) as TotalAnswers,
        (select avg(p2.Score) from Posts p2 where p2.ParentId = tq.Id and p2.PostTypeId = 2) as AvgAnswerScore,
        (select max(p2.Score) from Posts p2 where p2.ParentId = tq.Id and p2.PostTypeId = 2) as MaxAnswerScore
    from TopQuestions tq
    left join AcceptedAnswerDetails a on a.QuestionId = tq.Id
),
UserBadgeSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadgeCount,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadgeCount,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadgeCount,
        string_agg(distinct b.Name, ', ') filter (where b.TagBased = 1) as TagBasedBadges,
        string_agg(distinct b.Name, ', ') filter (where b.TagBased = 0) as NamedBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostLinkSummary as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Linked') as LinkedCount,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Duplicate') as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
),
QuestionWithLinks as (
    select
        qas.*,
        pls.LinkedCount,
        pls.DuplicateCount
    from QuestionAnswerStats qas
    left join PostLinkSummary pls on pls.PostId = qas.QuestionId
),
FinalResult as (
    select
        rua.UserId,
        rua.DisplayName,
        rua.Reputation,
        rua.CreationDate as UserCreationDate,
        rua.LastAccessDate,
        rua.QuestionCount,
        rua.AnswerCount,
        rua.CommentCount,
        rua.GoldBadges,
        rua.SilverBadges,
        rua.BronzeBadges,
        rua.TotalBountyGiven,
        ubs.GoldBadgeCount,
        ubs.SilverBadgeCount,
        ubs.BronzeBadgeCount,
        ubs.TagBasedBadges,
        ubs.NamedBadges,
        qwl.QuestionId,
        qwl.Title as QuestionTitle,
        qwl.QuestionScore,
        qwl.ViewCount as QuestionViewCount,
        qwl.TotalAnswers,
        qwl.AvgAnswerScore,
        qwl.MaxAnswerScore,
        qwl.AcceptedAnswerScore,
        qwl.AcceptedAnswerOwner,
        qwl.AcceptedAnswerComments,
        qwl.LinkedCount,
        qwl.DuplicateCount,
        row_number() over (partition by rua.UserId order by qwl.QuestionScore desc nulls last) as QuestionRankPerUser
    from RecursiveUserActivity rua
    left join UserBadgeSummary ubs on ubs.UserId = rua.UserId
    left join QuestionWithLinks qwl on qwl.OwnerUserId = rua.UserId
    where rua.Reputation > 1000
)
select *
from FinalResult
where QuestionRankPerUser <= 3
order by Reputation desc, QuestionScore desc nulls last, UserId, QuestionRankPerUser;