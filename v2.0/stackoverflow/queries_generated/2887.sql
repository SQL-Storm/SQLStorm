-- {"query": "2887.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1609} 
with RecursiveBadgeUsers as (
    select u.Id, u.DisplayName, u.Reputation, b.Class, b.Name as BadgeName, b.Date,
        row_number() over (partition by u.Id order by b.Date desc) as rn
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Class is not null
),
RecentPostsWithAnswerStats as (
    select 
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Title, p.Tags,
        p.AcceptedAnswerId, p.AnswerCount,
        -- Correlated subquery to count number of comments per post
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        -- Computed complex expression for engagement score
        (coalesce(p.Score,0)*2 + coalesce(p.ViewCount,0)/100 + coalesce((select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2),0)*3
        + coalesce((select count(*) from Comments c where c.PostId = p.Id),0)*1.5) as EngagementScore,
        -- Window function for ranking posts by engagement per day
        rank() over (partition by date_trunc('day', p.CreationDate) order by 
            (coalesce(p.Score,0)*2 + coalesce(p.ViewCount,0)/100 + coalesce((select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2),0)*3 + coalesce((select count(*) from Comments c where c.PostId = p.Id),0)*1.5) desc) as DailyEngagementRank
    from Posts p
    where p.CreationDate >= current_date - interval '30 days'
), LatestUserActivity as (
    select u.Id, u.DisplayName, u.Reputation, u.CreationDate,
        max(ph.CreationDate) as LastPostEditDate,
        max(v.CreationDate) as LastVoteDate,
        max(c.CreationDate) as LastCommentDate,
        -- Using greatest with coalesce to handle NULLs
        greatest(
            coalesce(max(ph.CreationDate), timestamp '1970-01-01'),
            coalesce(max(v.CreationDate), timestamp '1970-01-01'),
            coalesce(max(c.CreationDate), timestamp '1970-01-01')
        ) as LastActivityDate
    from Users u
    left join PostHistory ph on ph.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
), TagAggregates as (
    select
        t.TagName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        sum(p.ViewCount) filter (where p.PostTypeId = 1) as TotalQuestionViews,
        avg(p.Score) filter (where p.PostTypeId = 1) as AvgQuestionScore,
        min(p.CreationDate) as FirstSeen,
        max(p.CreationDate) as LastSeen
    from Tags t
    left join Posts p on p.Tags like concat('%<', t.TagName, '>%')
    group by t.TagName
), DuplicatePostPairs as (
    select pl.PostId, pl.RelatedPostId, pl.CreationDate,
        p1.Title as PostTitle, p2.Title as RelatedPostTitle
    from PostLinks pl
    inner join Posts p1 on p1.Id = pl.PostId
    inner join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3 -- Duplicate
), QuestionsWithAcceptedAnswerInfo as (
    select p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags,
        a.Id as AnswerId, a.Score as AnswerScore, a.CreationDate as AnswerCreationDate,
        u.DisplayName as OwnerName,
        case when p.ClosedDate is not null then 1 else 0 end as IsClosed
    from Posts p
    left join Posts a on a.Id = p.AcceptedAnswerId
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
),
RecentHotQuestions as (
    select q.*, row_number() over (order by q.ViewCount desc, q.Score desc) as HotRank
    from QuestionsWithAcceptedAnswerInfo q
    where q.CreationDate >= current_date - interval '7 days'
    and q.IsClosed = 0
)
select rph.Id as PostId,
       rph.Title,
       rph.CreationDate as PostCreated,
       rph.Score as PostScore,
       rph.ViewCount,
       rph.EngagementScore,
       rph.DailyEngagementRank,
       u.DisplayName as OwnerDisplayName,
       u.Reputation as OwnerReputation,
       ru.LastActivityDate,
       array_to_string(array(
           select distinct t.TagName from Tags t
           where rph.Tags like concat('%<',t.TagName,'>%')
           order by t.Count desc limit 3), ', ') as TopTags,
       coalesce(db.BadgeName, 'No Badge') as MostRecentBadgeName,
       coalesce(db.Class, 0) as BadgeClass,
       dp.RelatedPostId as DuplicateOf,
       dp.RelatedPostTitle,
       case when rph.AcceptedAnswerId is not null then 'Has Accepted Answer' else 'No Accepted Answer' end as AcceptedAnswerStatus,
       coalesce(qw.AnswerScore, 0) as AcceptedAnswerScore,
       coalesce(qw.AnswerCreationDate, timestamp '1970-01-01') as AcceptedAnswerCreated,
       case when rph.CommentCount > 5 then 'Highly Commented' else 'Less Commented' end as CommentPopularity,
       length(coalesce(rph.Title, '')) + length(coalesce(u.DisplayName, '')) as TitleOwnerNameLengthSum,
       upper(left(coalesce(rph.Title, ''), 10)) as TitleSnippet,
       concat(left(coalesce(u.DisplayName, ''), 5), '_', rph.Id) as OwnerPostCompositeKey
from RecentPostsWithAnswerStats rph
inner join Users u on u.Id = rph.OwnerUserId
left join LatestUserActivity ru on ru.Id = u.Id
left join RecursiveBadgeUsers db on db.Id = u.Id and db.rn = 1
left join DuplicatePostPairs dp on dp.PostId = rph.Id
left join QuestionsWithAcceptedAnswerInfo qw on qw.Id = rph.Id
where rph.DailyEngagementRank <= 50

union

select rhq.Id,
       rhq.Title,
       rhq.CreationDate,
       rhq.Score,
       rhq.ViewCount,
       null,
       null,
       rhq.OwnerName,
       null,
       null,
       null,
       null,
       null,
       null,
       rhq.AcceptedAnswerStatus,
       rhq.AnswerScore,
       rhq.AnswerCreationDate,
       null,
       null,
       null,
       null
from RecentHotQuestions rhq
order by PostCreated desc, EngagementScore desc nulls last
fetch first 100 rows only;