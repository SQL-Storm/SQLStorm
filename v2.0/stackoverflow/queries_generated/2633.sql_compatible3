with recursive RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        1 as Level,
        coalesce(t.WikiPostId, 0) as WikiPostReference
    from Tags t
    where t.IsModeratorOnly = false and t.IsRequired = false
    union all
    select 
        c.Id,
        c.TagName,
        c.Count,
        r.Level + 1,
        coalesce(c.WikiPostId, 0)
    from Tags c
    inner join RecursiveTagHierarchy r on c.WikiPostId = r.WikiPostReference
    where r.Level < 3
),
UserReputationAgg as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct b.Id) as BadgeCount,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        sum(v.VoteScore) as VoteScoreTotal
    from
        Users u
    left join Badges b on u.Id = b.UserId
    left join (
        select 
            p.OwnerUserId,
            sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end) as VoteScore
        from Posts p
        left join Votes v on v.PostId = p.Id
        where p.OwnerUserId is not null and p.OwnerUserId <> -1
        group by p.OwnerUserId
    ) v on u.Id = v.OwnerUserId
    group by u.Id, u.DisplayName, u.Reputation
),
PopularQuestions as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        rank() over (partition by substring(p.Tags from 2 for position('>' in substring(p.Tags from 2)) - 1) order by p.Score desc, p.ViewCount desc) as TagRank
    from Posts p
    where p.PostTypeId = 1 and p.Score >= 10 and p.ViewCount >= 1000
),
AnswersWithParent as (
    select
        a.Id,
        a.ParentId,
        a.CreationDate,
        a.Score,
        a.OwnerUserId,
        p.Title as ParentTitle,
        p.Tags as ParentTags
    from Posts a
    left join Posts p on a.ParentId = p.Id
    where a.PostTypeId = 2
),
ClosedQuestionsWithReason as (
    select
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReasonName
    from PostHistory ph
    inner join CloseReasonTypes crt on cast(ph.Comment as integer) = crt.Id
    where ph.PostHistoryTypeId = 10
),
AggregatedComments as (
    select
        c.PostId,
        count(*) as CommentCount,
        max(c.Score) as MaxCommentScore,
        sum(case when c.UserId is null then 1 else 0 end) as AnonymousComments
    from Comments c
    group by c.PostId
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(p.Id) filter (where p.PostTypeId = 1) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as QuestionsAsked,
        count(p.Id) filter (where p.PostTypeId = 2) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as AnswersGiven,
        row_number() over (partition by u.Id order by p.CreationDate desc) as LastPostRowNum
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
),
DistinctLinks as (
    select distinct
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        pl.CreationDate
    from PostLinks pl
    inner join LinkTypes lt on pl.LinkTypeId = lt.Id
),
QuestionsUnionAnswers as (
    select 
        Id, PostTypeId, OwnerUserId, CreationDate, Score, Title, Tags 
    from Posts 
    where PostTypeId in (1,2)
    intersect
    select 
        a.Id, a.PostTypeId, a.OwnerUserId, a.CreationDate, a.Score, p.Title, p.Tags
    from Posts a
    inner join Posts p on a.ParentId = p.Id
    where a.PostTypeId = 2
),
ComplexStringConditions as (
    select 
        p.Id,
        p.Title,
        p.Tags,
        case
            when p.Tags is null then 'No Tags'
            when p.Tags like '%<sql>%' then 'SQL Related'
            when char_length(p.Title) > 100 then 'Long Title'
            when lower(left(p.Title, 3)) in ('how', 'wha') or lower(left(p.Title, 4)) in ('what','when','whys') or lower(left(p.Title,5)) in ('where') then 'Question Starts With WH'
            else 'Other'
        end as TagCategory
    from Posts p
    where p.PostTypeId = 1
)
select distinct
    pq.Id as QuestionId,
    pq.Title as QuestionTitle,
    pq.CreationDate as QuestionCreationDate,
    ur.DisplayName as QuestionOwner,
    ur.Reputation as OwnerReputation,
    pq.Score as QuestionScore,
    pq.ViewCount as QuestionViews,
    pq.Tags as QuestionTags,
    ca.CommentCount,
    ca.MaxCommentScore,
    ca.AnonymousComments,
    cqr.CloseDate,
    cqr.CloseReasonName,
    aw.ParentTitle as AnsweredForQuestionTitle,
    aw.Score as AnswerScore,
    ul.LinkTypeName,
    ul.RelatedPostId,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.LastPostRowNum,
    ct.TagName,
    ct.Level as TagHierarchyLevel,
    ct.Count as TagUseCount,
    ua2.GoldBadges,
    ua2.SilverBadges,
    ua2.BronzeBadges,
    ua2.VoteScoreTotal,
    cs.TagCategory
from PopularQuestions pq
left join UserReputationAgg ur on pq.OwnerUserId = ur.UserId
left join AggregatedComments ca on ca.PostId = pq.Id
left join ClosedQuestionsWithReason cqr on cqr.PostId = pq.Id
left join AnswersWithParent aw on aw.ParentId = pq.Id
left join DistinctLinks ul on ul.PostId = pq.Id
left join UserActivityWindow ua on ua.UserId = pq.OwnerUserId and ua.LastPostRowNum = 1
left join UserReputationAgg ua2 on ua2.UserId = pq.OwnerUserId
left join RecursiveTagHierarchy ct on position(ct.TagName in pq.Tags) > 0
left join ComplexStringConditions cs on cs.Id = pq.Id
where 
    (ur.Reputation > 500 AND pq.Score > 20)
    or (cqr.CloseDate is not null and cqr.CloseReasonName like '%Duplicate%')
order by pq.Score desc, pq.ViewCount desc
limit 100;