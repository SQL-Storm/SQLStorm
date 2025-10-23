-- {"query": "764.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1074} 
with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc) as rn
    from Users u
    left join Badges b on u.Id = b.UserId
    where u.Reputation > 1000
),
LatestUserActivity as (
    select
        u.Id as UserId,
        max(coalesce(p.LastActivityDate, c.CreationDate, ph.CreationDate)) as LastActivityDate
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    left join Comments c on u.Id = c.UserId
    left join PostHistory ph on u.Id = ph.UserId
    group by u.Id
),
TopQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AnswerCount,
        dense_rank() over (order by p.Score desc, p.ViewCount desc) as RankByScoreView
    from Posts p
    where p.PostTypeId = 1
      and p.ClosedDate is null
      and p.Score > 10
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        pl.LinkTypeId,
        pt1.Title as PostTitle,
        pt2.Title as RelatedPostTitle
    from PostLinks pl
    join Posts pt1 on pl.PostId = pt1.Id
    join Posts pt2 on pl.RelatedPostId = pt2.Id
    where pl.LinkTypeId = 3
),
UserActivityStats as (
    select
        u.Id as UserId,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesGiven,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesGiven
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    left join Comments c on u.Id = c.UserId
    left join Votes v on u.Id = v.UserId
    group by u.Id
),
QuestionWithAcceptedAnswerAndBadge as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.Score,
        q.AnswerCount,
        a.Id as AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        r.DisplayName as OwnerDisplayName,
        b.BadgeName,
        b.Class
    from Posts q
    left join Posts a on q.AcceptedAnswerId = a.Id
    left join Users r on q.OwnerUserId = r.Id
    left join RecursiveUserBadges b on r.Id = b.UserId and b.rn = 1
    where q.PostTypeId = 1
      and q.AcceptedAnswerId is not null
      and q.Score > 5
),
RankedQuestions as (
    select
        q.*,
        row_number() over (partition by q.OwnerUserId order by q.Score desc) as rn_by_user
    from QuestionWithAcceptedAnswerAndBadge q
)
select
    rq.QuestionId,
    rq.Title,
    rq.OwnerUserId,
    rq.OwnerDisplayName,
    rq.Score as QuestionScore,
    rq.AnswerCount,
    rq.AcceptedAnswerId,
    rq.AcceptedAnswerScore,
    rq.BadgeName,
    rq.Class as BadgeClass,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.CommentCount,
    ua.UpVotesGiven,
    ua.DownVotesGiven,
    la.LastActivityDate,
    dup.PostTitle as DuplicatePostTitle,
    dup.RelatedPostTitle as DuplicateRelatedPostTitle,
    case
      when rq.BadgeName is null then 'No Badge'
      else concat('Badge: ', rq.BadgeName, ' (Class ', rq.Class, ')')
    end as BadgeDescription,
    case
      when rq.AcceptedAnswerScore > rq.Score then 'Accepted answer scored higher'
      when rq.AcceptedAnswerScore = rq.Score then 'Accepted answer scored equal'
      else 'Question scored higher'
    end as ScoreComparison,
    substring(rq.Title from 1 for 20) || '...' as TitleSnippet
from RankedQuestions rq
join UserActivityStats ua on rq.OwnerUserId = ua.UserId
join LatestUserActivity la on rq.OwnerUserId = la.UserId
left join DuplicateLinks dup on dup.PostId = rq.QuestionId
where rq.rn_by_user = 1
  and (rq.BadgeName is not null or ua.QuestionCount > 5)
order by la.LastActivityDate desc, rq.Score desc
limit 100;