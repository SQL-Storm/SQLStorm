-- {"query": "2468.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1374} 
with UserRankedBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Class, b.Date desc) as rn
    from Users u
    left join Badges b on b.UserId = u.Id
    where b.TagBased = 0
),
TopBadges as (
    select UserId, BadgeName, Class
    from UserRankedBadges
    where rn <= 3
),
QuestionAnswerStats as (
    select
        p.Id as QuestionId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score as QuestionScore,
        coalesce(p.AnswerCount,0) as AnswerCount,
        coalesce(p.FavoriteCount,0) as FavoriteCount,
        -- Calculate avg score of answers per question using correlated subquery
        (
            select avg(a.Score)
            from Posts a
            where a.ParentId = p.Id and a.PostTypeId = 2
        ) as AvgAnswerScore,
        -- Most recent comment on the question
        (
            select c.Text
            from Comments c
            where c.PostId = p.Id
            order by c.CreationDate desc
            limit 1
        ) as LastCommentText,
        -- Number of distinct commenters on queston and its answers
        (
            select count(distinct c2.UserId)
            from Comments c2
            join Posts ap on ap.Id = c2.PostId and ap.PostTypeId in (1,2)
            where (ap.Id = p.Id or ap.ParentId = p.Id) and c2.UserId is not null
        ) as DistinctCommentersCount
    from Posts p
    where p.PostTypeId = 1
),
LatestPostHistory as (
    select ph.PostId, ph.PostHistoryTypeId, ph.CreationDate,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc, ph.Id desc) as rn
    from PostHistory ph
),
QuestionWithLatestHistory as (
    select qas.*, ph.PostHistoryTypeId as LatestPostHistoryType
    from QuestionAnswerStats qas
    left join LatestPostHistory ph on ph.PostId = qas.QuestionId and ph.rn = 1
),
UserActivityWindow as (
    select
        u.Id,
        u.DisplayName,
        u.CreationDate,
        count(p.Id) filter (where p.PostTypeId = 1) over (partition by u.Id order by u.CreationDate rows between unbounded preceding and current row) as QuestionsCount,
        count(p.Id) filter (where p.PostTypeId = 2) over (partition by u.Id order by u.CreationDate rows between unbounded preceding and current row) as AnswersCount,
        count(c.Id) over (partition by u.Id order by u.CreationDate rows between unbounded preceding and current row) as CommentsCount
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.CreationDate >= u.CreationDate
    left join Comments c on c.UserId = u.Id and c.CreationDate >= u.CreationDate
),
UserLinkSummary as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        count(distinct pl.Id) over (partition by pl.PostId) as LinkCountPerPost,
        count(distinct pl.Id) over (partition by pl.RelatedPostId) as LinkCountPerRelatedPost
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
),
ComplexSearch as (
    select distinct p.Id, p.Title, p.Tags,
        length(p.Body) as BodyLength,
        position('select' in lower(p.Body)) as PosSelect,
        case when p.ClosedDate is null then 'Open' else 'Closed' end as Status,
        strpos(p.Tags, '<sql>') > 0 as ContainsSqlTag,
        coalesce(p.Score,0) * coalesce(p.ViewCount,0) / nullif(GREATEST(LENGTH(p.Body),1), 0) as WeightedScore
    from Posts p
    where p.PostTypeId = 1
    and (p.Tags like '%<sql>%'
         or p.Title ilike '%performance%'
         or p.Body ilike '%join%'
         or p.Body ilike '%subquery%')
)
select
    qwlq.QuestionId,
    qwlq.Title,
    qwlq.QuestionScore,
    qwlq.AnswerCount,
    qwlq.FavoriteCount,
    coalesce(qwlq.AvgAnswerScore, 0) as AvgAnswerScore,
    qwlq.LastCommentText,
    qwlq.DistinctCommentersCount,
    qwlq.LatestPostHistoryType,
    ts.BadgeName,
    ts.Class as BadgeClass,
    ul.LinkTypeName,
    ul.LinkCountPerPost,
    ul.LinkCountPerRelatedPost,
    usq.Status,
    usq.WeightedScore,
    usq.PosSelect,
    us.ActivitySummary,
    row_number() over (partition by qwlq.OwnerUserId order by qwlq.QuestionScore desc) as UserTopQuestionRank
from QuestionWithLatestHistory qwlq
left join TopBadges ts on ts.UserId = qwlq.OwnerUserId
left join UserLinkSummary ul on ul.PostId = qwlq.QuestionId
left join ComplexSearch usq on usq.Id = qwlq.QuestionId
left join (
    select ua.Id, ua.DisplayName, 
        concat(
            'Q:', coalesce(nullif(cast(ua.QuestionsCount as varchar), ''), '0'),
            '|A:', coalesce(nullif(cast(ua.AnswersCount as varchar), ''), '0'),
            '|C:', coalesce(nullif(cast(ua.CommentsCount as varchar), ''), '0')
        ) as ActivitySummary
    from UserActivityWindow ua
) us on us.Id = qwlq.OwnerUserId
where qwlq.AnswerCount > 0
and (ts.Class is null or ts.Class <= 2)
and (usq.Status = 'Open' or usq.WeightedScore > 1000)
order by qwlq.QuestionScore desc, qwlq.AnswerCount desc, ts.Class asc nulls last;