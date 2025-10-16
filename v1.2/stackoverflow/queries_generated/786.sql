-- {"query": "786.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1441} 
with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class as BadgeClass,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.TagBased = 0 or b.TagBased is null
),
LatestPostEdits as (
    select
        ph.PostId,
        max(ph.CreationDate) as LastEditDate
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6,7,8,9)
    group by ph.PostId
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        count(a.Id) as AnswerCount,
        coalesce(sum(a.Score), 0) as TotalAnswerScore,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        max(case when a.OwnerUserId = q.OwnerUserId then 1 else 0 end) as HasSelfAnswer
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.Tags
),
UserActivityWindows as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativePosts,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativeQuestions,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativeAnswers,
        row_number() over (partition by u.Id order by p.CreationDate desc) as RecentPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        lt.Name as LinkTypeName
    from PostLinks pl
    join Posts p1 on pl.PostId = p1.Id
    join Posts p2 on pl.RelatedPostId = p2.Id
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    where pl.LinkTypeId = 3 -- Duplicate
),
QuestionsWithCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    where ph.PostHistoryTypeId = 10 -- Post Closed
),
TopTags as (
    select
        t.TagName,
        t.Count,
        p.Title as ExcerptTitle,
        p.Body as ExcerptBody
    from Tags t
    left join Posts p on t.ExcerptPostId = p.Id
    where t.Count > 1000
    order by t.Count desc
    limit 50
),
UserBadgesPivot as (
    select
        UserId,
        max(case when BadgeClass = 1 then 1 else 0 end) as HasGold,
        max(case when BadgeClass = 2 then 1 else 0 end) as HasSilver,
        max(case when BadgeClass = 3 then 1 else 0 end) as HasBronze
    from Badges
    group by UserId
)
select distinct
    qas.QuestionId,
    qas.Title as QuestionTitle,
    qas.OwnerUserId,
    u.DisplayName as OwnerName,
    qas.CreationDate as QuestionCreated,
    qas.QuestionScore,
    qas.ViewCount,
    qas.AnswerCount,
    qas.TotalAnswerScore,
    qas.MaxAnswerScore,
    qas.AvgAnswerScore,
    qas.HasSelfAnswer,
    close.CloseReason,
    close.CloseDate,
    dup.RelatedPostId as DuplicateOfPostId,
    dup.RelatedPostTitle as DuplicateOfPostTitle,
    rub.BadgeName as RecentBadgeEarned,
    lubp.HasGold,
    lubp.HasSilver,
    lubp.HasBronze,
    row_number() over (partition by qas.OwnerUserId order by qas.QuestionScore desc, qas.ViewCount desc) as UserQuestionRank,
    concat(
        'Tags: ',
        coalesce(qas.Tags, 'None')
    ) as TagsList,
    -- String manipulation example: extract first tag if tags are XML-like "<tag1><tag2>"
    substring(qas.Tags from '<([^>]+)>') as FirstTag,
    -- Correlated subquery example: count comments for question
    (select count(*) from Comments c where c.PostId = qas.QuestionId) as CommentCount,
    -- Window function to compute average score of all user's questions
    avg(qas.QuestionScore) over (partition by qas.OwnerUserId) as AvgUserQuestionScore,
    -- Complex predicate example: questions with high score or many views or with accepted answer with score > 5
    case
        when qas.QuestionScore > 50 or qas.ViewCount > 10000 then 'High Impact'
        when exists (select 1 from Posts a where a.Id = qas.AcceptedAnswerId and a.Score > 5) then 'Accepted High Score Answer'
        else 'Normal'
    end as ImpactCategory
from QuestionAnswerStats qas
join Users u on u.Id = qas.OwnerUserId
left join QuestionsWithCloseReasons close on close.PostId = qas.QuestionId
left join DuplicateLinks dup on dup.PostId = qas.QuestionId
left join RecursiveUserBadges rub on rub.UserId = u.Id and rub.BadgeRank = 1
left join UserBadgesPivot lubp on lubp.UserId = u.Id
where qas.AnswerCount > 0
  and (qas.QuestionScore > 10 or qas.ViewCount > 5000)
order by qas.QuestionScore desc, qas.ViewCount desc
limit 100;