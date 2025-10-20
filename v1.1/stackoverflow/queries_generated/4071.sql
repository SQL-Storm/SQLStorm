-- {"query": "4071.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1416} 
with recursive UserBadgeSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
TopUsersLatestBadge as (
    select
        UserId,
        DisplayName,
        Reputation,
        GoldBadges,
        SilverBadges,
        BronzeBadges
    from UserBadgeSummary
    where BadgeRank = 1
),
QuestionStats as (
    select 
        p.Id as QuestionId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        u.DisplayName as OwnerDisplayName,
        coalesce(
            (select max(ph.CreationDate)
             from PostHistory ph
             where ph.PostId = p.Id
               and ph.PostHistoryTypeId in (4,5,6) -- Edit Title, Body, Tags
            ), p.LastEditDate) as LastEditOrActivity,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as OwnerTopQuestionRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1 -- Questions only
        and p.Score >= 0
        and p.ClosedDate is null
),
LatestAnswerPerQuestion as (
    select distinct on (ParentId)
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        a.OwnerUserId as AnswerOwnerUserId,
        u.DisplayName as AnswerOwnerDisplayName
    from Posts a
    left join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2 -- Answers only
    order by a.ParentId, a.CreationDate desc
),
QuestionDuplicates as (
    select 
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId,
        qd.Title as DuplicateTitle,
        qo.Title as OriginalTitle,
        pl.CreationDate as LinkCreationDate
    from PostLinks pl
    inner join Posts qd on qd.Id = pl.PostId and qd.PostTypeId = 1
    inner join Posts qo on qo.Id = pl.RelatedPostId and qo.PostTypeId = 1
    where pl.LinkTypeId = 3 -- Duplicate link type
),
UserCommentsStats as (
    select 
        c.UserId,
        u.DisplayName,
        count(c.Id) as TotalComments,
        avg(length(c.Text)) as AvgCommentLength,
        sum(case when c.Text is null or trim(c.Text) = '' then 1 else 0 end) as NullOrEmptyComments
    from Comments c
    left join Users u on u.Id = c.UserId
    group by c.UserId, u.DisplayName
),
FinalCombined as (
    select
        qu.QuestionId,
        qu.Title,
        qu.Tags,
        qu.CreationDate as QuestionCreation,
        qu.Score as QuestionScore,
        qu.ViewCount,
        qu.AnswerCount,
        qu.OwnerUserId,
        qu.OwnerDisplayName,
        lub.GoldBadges,
        lub.SilverBadges,
        lub.BronzeBadges,
        lub.Reputation,
        la.AnswerId,
        la.AnswerScore,
        la.AnswerCreationDate,
        la.AnswerOwnerUserId,
        la.AnswerOwnerDisplayName,
        qc.TotalComments,
        qc.AvgCommentLength,
        qc.NullOrEmptyComments,
        qd.OriginalQuestionId,
        qd.OriginalTitle
    from QuestionStats qu
    left join TopUsersLatestBadge lub on lub.UserId = qu.OwnerUserId
    left join LatestAnswerPerQuestion la on la.QuestionId = qu.QuestionId
    left join UserCommentsStats qc on qc.UserId = qu.OwnerUserId
    left join QuestionDuplicates qd on qd.DuplicateQuestionId = qu.QuestionId
    where qu.OwnerTopQuestionRank <= 3 -- top 3 questions per owner by score
)
select
    fc.QuestionId,
    left(fc.Title, 100) || case when length(fc.Title) > 100 then '...' else '' end as ShortTitle,
    fc.Tags,
    fc.QuestionCreation,
    fc.QuestionScore,
    fc.ViewCount,
    fc.AnswerCount,
    fc.OwnerUserId,
    coalesce(fc.OwnerDisplayName, 'Unknown User') as QuestionOwner,
    fc.GoldBadges,
    fc.SilverBadges,
    fc.BronzeBadges,
    fc.Reputation,
    fc.AnswerId,
    fc.AnswerScore,
    fc.AnswerCreationDate,
    coalesce(fc.AnswerOwnerDisplayName, 'Unknown User') as AnswerOwner,
    fc.TotalComments,
    round(fc.AvgCommentLength,2) as AvgCommentLength,
    fc.NullOrEmptyComments,
    fc.OriginalQuestionId,
    left(fc.OriginalTitle, 80) || case when length(fc.OriginalTitle) > 80 then '...' else '' end as OriginalTitleShort,
    -- Complex calculated column: Weighted activity score
    round(
        (coalesce(fc.QuestionScore,0) * 0.4) +
        (coalesce(fc.AnswerScore,0) * 0.3) +
        (fc.ViewCount / nullif(fc.AnswerCount + 1,0)) * 0.2 +
        (coalesce(fc.GoldBadges,0) * 5) +
        (coalesce(fc.SilverBadges,0) * 2) +
        (coalesce(fc.BronzeBadges,0) * 1) -
        (fc.NullOrEmptyComments * 3),
    3) as WeightedActivityScore
from FinalCombined fc
where 
    (fc.QuestionScore > 5 or fc.AnswerScore > 5 or fc.GoldBadges > 0)
    and (fc.OriginalQuestionId is null or fc.QuestionCreation > (select max(CreationDate) from Posts where Id = fc.OriginalQuestionId))
order by WeightedActivityScore desc NULLS LAST, fc.QuestionCreation desc
limit 50;