-- {"query": "4097.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1405} 
with RecursivePostsCTE as (
    select p.Id, p.PostTypeId, p.AcceptedAnswerId, p.ParentId, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId,
           1 as Depth,
           array[p.Id] as Path
    from Posts p
    where p.PostTypeId = 1 and p.Score > 10 and p.CreationDate > now() - interval '1 year'

    union all

    select c.Id, c.PostTypeId, c.AcceptedAnswerId, c.ParentId, c.CreationDate, c.Score, c.ViewCount, c.OwnerUserId,
           r.Depth + 1,
           r.Path || c.Id
    from Posts c
    join RecursivePostsCTE r on c.ParentId = r.Id
    where c.Score > 5 and not c.Id = any(r.Path) and r.Depth < 3
),
UserBadgeCounts as (
    select b.UserId,
           count(*) filter (where b.Class = 1) as GoldBadges,
           count(*) filter (where b.Class = 2) as SilverBadges,
           count(*) filter (where b.Class = 3) as BronzeBadges,
           bool_or(b.TagBased) as HasTagBasedBadge
    from Badges b
    group by b.UserId
),
LatestPostHistory as (
    select ph.PostId, ph.PostHistoryTypeId, ph.CreationDate,
           row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
    from PostHistory ph
    where ph.PostHistoryTypeId in (10,11,19,20)
),
FilteredPostHistory as (
    select lph.PostId, lph.PostHistoryTypeId, lph.CreationDate
    from LatestPostHistory lph
    where lph.rn = 1
),
UserActivityWindow as (
    select u.Id as UserId, u.DisplayName,
           count(p.Id) filter (where p.PostTypeId = 1) over (partition by u.Id order by p.CreationDate rows between 29 preceding and current row) as QuestionsLast30Days,
           count(p.Id) filter (where p.PostTypeId = 2) over (partition by u.Id order by p.CreationDate rows between 29 preceding and current row) as AnswersLast30Days,
           max(u.Reputation) over (partition by u.Id) as UserReputation
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
TopScoringAnswers as (
    select a.Id, a.ParentId, a.Score,
           row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    where a.PostTypeId = 2
),
QuestionAnswerSummary as (
    select q.Id as QuestionId,
           q.Title,
           q.Tags,
           q.Score as QuestionScore,
           q.ViewCount as QuestionViews,
           q.OwnerUserId,
           coalesce(sum(a.Score), 0) as TotalAnswerScore,
           max(a.Score) as MaxAnswerScore,
           count(a.Id) as AnswerCount
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.Tags, q.Score, q.ViewCount, q.OwnerUserId
),
DuplicatedQuestions as (
    select pl.PostId as QuestionId, pl.RelatedPostId as DuplicateOf
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    where exists (
        select 1 from Posts p where p.Id = pl.PostId and p.PostTypeId = 1
    )
    and exists (
        select 1 from Posts rp where rp.Id = pl.RelatedPostId and rp.PostTypeId = 1
    )
)
select qas.QuestionId,
       left(qas.Title, 100) || case when length(qas.Title) > 100 then '...' else '' end as ShortTitle,
       qas.QuestionScore,
       qas.QuestionViews,
       qas.AnswerCount,
       qas.TotalAnswerScore,
       qas.MaxAnswerScore,
       coalesce(dq.DuplicateOf, null) as DuplicateOfQuestionId,
       ub.GoldBadges,
       ub.SilverBadges,
       ub.BronzeBadges,
       ub.HasTagBasedBadge,
       fa.Id as TopAnswerId,
       fa.Score as TopAnswerScore,
       fa.CreationDate as TopAnswerCreationDate,
       fph.PostHistoryTypeId as LatestClosureOrProtectionType,
       fph.CreationDate as LatestClosureOrProtectionDate,
       ua.QuestionsLast30Days,
       ua.AnswersLast30Days,
       ua.UserReputation,
       string_agg(distinct pt.Name, ', ') as PostTypesInThread,
       max(phwp.PostHistoryTypeId) as MaxPostHistoryTypeInThread
from QuestionAnswerSummary qas
left join Users u on u.Id = qas.OwnerUserId
left join UserBadgeCounts ub on ub.UserId = qas.OwnerUserId
left join TopScoringAnswers fa on fa.ParentId = qas.QuestionId and fa.AnswerRank = 1
left join FilteredPostHistory fph on fph.PostId = qas.QuestionId
left join DuplicatedQuestions dq on dq.QuestionId = qas.QuestionId
left join UserActivityWindow ua on ua.UserId = qas.OwnerUserId
left join Posts pth on pth.Id = any(
  select Id from RecursivePostsCTE where Path[1] = qas.QuestionId
)
left join PostTypes pt on pt.Id = pth.PostTypeId
left join PostHistory phwp on phwp.PostId = pth.Id
group by qas.QuestionId, qas.Title, qas.QuestionScore, qas.QuestionViews, qas.AnswerCount, qas.TotalAnswerScore, qas.MaxAnswerScore, dq.DuplicateOf, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ub.HasTagBasedBadge, fa.Id, fa.Score, fa.CreationDate, fph.PostHistoryTypeId, fph.CreationDate, ua.QuestionsLast30Days, ua.AnswersLast30Days, ua.UserReputation
having coalesce(qas.AnswerCount, 0) > 0
order by qas.TotalAnswerScore desc, qas.QuestionScore desc
limit 100;