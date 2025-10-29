-- {"query": "2401.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1245} 
with Recursive CTE_RecentActivity as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Tags,
        p.Title,
        p.AcceptedAnswerId,
        ph.PostHistoryTypeId,
        ph.CreationDate as HistoryDate,
        ph.UserId as EditorUserId
    from Posts p
    left join PostHistory ph on p.Id = ph.PostId and ph.CreationDate > current_date - interval '30 days'
    where p.PostTypeId in (1,2)
    union all
    select
        r.PostId,
        r.PostTypeId,
        r.CreationDate,
        r.Score,
        r.ViewCount,
        r.OwnerUserId,
        r.Tags,
        r.Title,
        r.AcceptedAnswerId,
        ph.PostHistoryTypeId,
        ph.CreationDate as HistoryDate,
        ph.UserId as EditorUserId
    from CTE_RecentActivity r
    join PostHistory ph on r.PostId = ph.PostId and ph.CreationDate > r.HistoryDate
    where ph.Id > r.PostId -- break infinite loops
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Name,
        b.Class,
        count(*) as BadgeCount,
        row_number() over (partition by b.UserId order by b.Class, count(*) desc) as rn
    from Badges b
    where b.Date > current_date - interval '365 days'
    group by b.UserId, b.Name, b.Class
),
UserReputationWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        sum(coalesce(v.BountyAmount,0)) over (partition by u.Id order by v.CreationDate rows between 30 preceding and current row) as BountySum30Days,
        count(distinct case when v.VoteTypeId=5 then v.Id else null end) over (partition by u.Id order by v.CreationDate rows between 60 preceding and current row) as FavoritesReceived60Days
    from Users u
    left join Votes v on v.UserId = u.Id and v.CreationDate > current_date - interval '60 days'
),
DupPostLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        lt.Name as LinkTypeName
    from PostLinks pl
    inner join LinkTypes lt on pl.LinkTypeId = lt.Id
    where pl.LinkTypeId = 3
),
PostWithCommentsCount as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.OwnerUserId,
        count(c.Id) as CommentCount
    from Posts p
    left join Comments c on p.Id = c.PostId
    group by p.Id, p.PostTypeId, p.Title, p.OwnerUserId
),
RankedAnswers as (
    select
        a.Id,
        a.ParentId,
        a.Score,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank,
        count(*) over (partition by a.ParentId) as TotalAnswers
    from Posts a
    where a.PostTypeId = 2
),
QuestionsWithTopAnswer as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.OwnerUserId,
        ra.Id as TopAnswerId,
        ra.Score as TopAnswerScore,
        ra.AnswerRank,
        ra.TotalAnswers
    from Posts q
    left join RankedAnswers ra on q.Id = ra.ParentId and ra.AnswerRank = 1
    where q.PostTypeId = 1
),
ComplexStringTags as (
    select
        Id,
        Tags,
        regexp_replace(
          coalesce(Tags, ''),
          '<([^>]+)>',
          upper('\\1'),
          'g'
        ) as UpperTags,
        array_length(string_to_array(coalesce(Tags, ''), '><'), 1) as TagCount
    from Posts
    where PostTypeId = 1
)
select distinct
    q.QuestionId,
    q.Title,
    q.Tags,
    cmt.CommentCount,
    dup.PostId as DuplicatePostId,
    dup.RelatedPostId as DuplicateRelatedPostId,
    dup.LinkTypeName,
    rb.Name as TopBadgeName,
    rb.Class as TopBadgeClass,
    urw.Reputation,
    urw.BountySum30Days,
    urw.FavoritesReceived60Days,
    q.TopAnswerId,
    q.TopAnswerScore,
    q.TotalAnswers,
    cs.UpperTags,
    cs.TagCount,
    case
        when q.TopAnswerScore > 100 then 'Hot Answer'
        when q.TotalAnswers > 10 then 'Popular Question'
        else 'Normal'
    end as PopularityFlag
from QuestionsWithTopAnswer q
left join PostWithCommentsCount cmt on q.QuestionId = cmt.Id
left join DupPostLinks dup on q.QuestionId = dup.PostId
left join UserBadgeCounts rb on q.OwnerUserId = rb.UserId and rb.rn = 1
left join UserReputationWindow urw on q.OwnerUserId = urw.Id
left join ComplexStringTags cs on q.QuestionId = cs.Id
where
    (q.Tags is not null and q.Tags like '%<sql>%')
    and (urw.Reputation > 500 or urw.BountySum30Days > 0)
    and (
        (rb.Class = 1) -- Gold badges owners
        or (q.TotalAnswers > 5 and q.TopAnswerScore > 10)
    )
order by q.TopAnswerScore desc nulls last, cmt.CommentCount desc nulls last
limit 100;