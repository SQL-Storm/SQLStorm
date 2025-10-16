-- {"query": "1210.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1169} 
with RecursiveUserVotes as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        v.VoteTypeId,
        v.CreationDate as VoteDate,
        row_number() over (partition by u.Id order by v.CreationDate desc) as VoteRank
    from Users u
    inner join Votes v on v.UserId = u.Id
    inner join Posts p on p.Id = v.PostId
    where v.VoteTypeId in (2,3) -- upvote or downvote
  union all
    select
        ruv.UserId,
        ruv.DisplayName,
        p.Id,
        p.PostTypeId,
        v.VoteTypeId,
        v.CreationDate,
        ruv.VoteRank + 1
    from RecursiveUserVotes ruv
    inner join Votes v on v.UserId = ruv.UserId and v.CreationDate < ruv.VoteDate
    inner join Posts p on p.Id = v.PostId
    where ruv.VoteRank < 5
), UserBadgeRanks as (
    select
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        dense_rank() over (partition by b.UserId order by b.Class) as BadgeRank
    from Badges b
    where b.TagBased = 0
), PostScoreStats as (
    select
        p.OwnerUserId,
        avg(p.Score) as AvgScore,
        max(p.Score) as MaxScore,
        sum(case when p.Score > 10 then 1 else 0 end) as HighScorePostCount
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
), QuestionAnswerCounts as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionDate,
        count(a.Id) as AnswersCount,
        sum(a.Score) as AnswersScoreSum,
        q.ViewCount,
        (select count(*) from Comments c where c.PostId = q.Id and c.UserId is null) as AnonymousCommentCount,
        coalesce(q.Tags, '<null>') as QuestionTags
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2 -- answers
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.ViewCount, q.Tags
), RankedUsers as (
    select distinct
        u.Id,
        u.DisplayName,
        u.Reputation,
        us.AvgScore,
        us.MaxScore,
        us.HighScorePostCount,
        rank() over (order by u.Reputation desc, us.AvgScore desc nulls last) as UserRank
    from Users u
    left join PostScoreStats us on us.OwnerUserId = u.Id
    where u.Reputation > 1000
)
select
    ru.Id as UserId,
    ru.DisplayName,
    ru.UserRank,
    ru.Reputation,
    ru.AvgScore,
    ru.MaxScore,
    ru.HighScorePostCount,
    ub.BadgeName,
    ub.Class as BadgeClass,
    qa.QuestionId,
    qa.Title as QuestionTitle,
    qa.QuestionDate,
    qa.AnswersCount,
    qa.AnswersScoreSum,
    qa.ViewCount,
    qa.AnonymousCommentCount,
    qa.QuestionTags,
    string_agg(distinct lt.Name, ', ' order by lt.Name) as LinkTypesUsed,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as TotalUpVotesGiven,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as TotalDownVotesGiven,
    coalesce(phc.CloseCount, 0) as CloseVotesCasted
from RankedUsers ru
left join UserBadgeRanks ub on ub.UserId = ru.Id and ub.BadgeRank = 1
left join QuestionAnswerCounts qa on qa.AnswersCount > 0 
    and qa.AnswersCount <= least(5, 10) -- limit join scope
    and qa.QuestionTags like '%' || (select top 1 TagName from Tags where Count > 100 order by Count desc) || '%' -- popular tag filter concept
left join PostLinks pl on pl.PostId = qa.QuestionId or pl.RelatedPostId = qa.QuestionId
left join LinkTypes lt on lt.Id = pl.LinkTypeId
left join Votes v on v.UserId = ru.Id and v.CreationDate >= ru.Reputation::bigint::text::timestamp - interval '365 day'
left join (
    select UserId, count(*) as CloseCount
    from PostHistory ph
    where PostHistoryTypeId = 10 -- Post Closed
    group by UserId
) phc on phc.UserId = ru.Id
group by
    ru.Id, ru.DisplayName, ru.UserRank, ru.Reputation, ru.AvgScore, ru.MaxScore, ru.HighScorePostCount,
    ub.BadgeName, ub.Class,
    qa.QuestionId, qa.Title, qa.QuestionDate, qa.AnswersCount, qa.AnswersScoreSum, qa.ViewCount, qa.AnonymousCommentCount, qa.QuestionTags, phc.CloseCount
having
    ru.Reputation > 5000
order by
    ru.UserRank asc,
    qa.ViewCount desc nulls last,
    qa.AnswersScoreSum desc nulls last
limit 50;