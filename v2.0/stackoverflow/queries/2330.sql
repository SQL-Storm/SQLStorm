-- {"query": "2330.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 998} 
with RecursiveViewedQuestions as (
    select p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, coalesce(p.ViewCount,0) as ViewCount,
        ROW_NUMBER() over (partition by p.OwnerUserId order by p.CreationDate desc) as rn
    from Posts p
    where p.PostTypeId = 1 and p.ViewCount is not null
    and p.CreationDate > cast('2024-10-01' as date) - interval '365 day'
),
BadgeCounts as (
    select UserId,
        sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges
    group by UserId
),
LatestPostHistory as (
    select ph.PostId,
        max(ph.CreationDate) as LastEditDate
    from PostHistory ph
    group by ph.PostId
),
UserQuestionStats as (
    select u.Id as UserId, u.DisplayName, u.Reputation, u.CreationDate, u.Location,
        count(distinct q.Id) as QuestionsAsked,
        count(distinct a.Id) as AnswersGiven,
        sum(coalesce(q.Score,0)) as TotalQuestionScore,
        sum(coalesce(a.Score,0)) as TotalAnswerScore,
        max(q.CreationDate) as LastQuestionDate,
        max(a.CreationDate) as LastAnswerDate,
        bc.GoldBadges, bc.SilverBadges, bc.BronzeBadges
    from Users u
    left join Posts q on q.OwnerUserId = u.Id and q.PostTypeId = 1
    left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    left join BadgeCounts bc on bc.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, bc.GoldBadges, bc.SilverBadges, bc.BronzeBadges
),
QuestionAnswerLink as (
    select q.Id as QuestionId, q.Title, q.OwnerUserId as QuestionOwner, a.Id as AnswerId, a.OwnerUserId as AnswerOwner,
        a.Score as AnswerScore, a.CreationDate as AnswerDate,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
TopAnswersPerQuestion as (
    select QuestionId, Title, QuestionOwner, AnswerId, AnswerOwner, AnswerScore, AnswerDate
    from QuestionAnswerLink
    where AnswerRank = 1
),
DuplicateQuestionPairs as (
    select pl.PostId as DuplicateQuestionId, pl.RelatedPostId as OriginalQuestionId, pl.CreationDate as LinkCreationDate
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    join Posts p1 on p1.Id = pl.PostId and p1.PostTypeId = 1
    join Posts p2 on p2.Id = pl.RelatedPostId and p2.PostTypeId = 1
)
select uqs.UserId, uqs.DisplayName, uqs.Reputation, uqs.Location,
    uqs.QuestionsAsked, uqs.AnswersGiven, uqs.TotalQuestionScore, uqs.TotalAnswerScore,
    uqs.GoldBadges, uqs.SilverBadges, uqs.BronzeBadges,
    tq.Title as MostViewedQuestionTitle,
    tq.ViewCount as MostViewedQuestionViews,
    ta.AnswerScore as TopAnswerScore,
    ta.AnswerDate as TopAnswerDate,
    dup.OriginalQuestionId,
    case when uqs.Location is null then 'Location Unknown' else concat('Location: ', uqs.Location) end as LocationTag
from UserQuestionStats uqs
left join RecursiveViewedQuestions tq on tq.OwnerUserId = uqs.UserId and tq.rn = 1
left join TopAnswersPerQuestion ta on ta.QuestionOwner = uqs.UserId and ta.AnswerScore > 0
left join DuplicateQuestionPairs dup on dup.DuplicateQuestionId = tq.Id
where uqs.QuestionsAsked > 10
and uqs.Reputation > 1000
and (ta.AnswerScore is null or ta.AnswerScore > 5)
order by uqs.Reputation desc, uqs.QuestionsAsked desc
limit 100;