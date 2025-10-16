-- {"query": "909.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1329} 
with RecursiveTagHierarchy as (
    select 
        t.Id,
        t.TagName,
        array[t.TagName] as TagPath,
        1 as Level
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0

    union all

    select
        t2.Id,
        t2.TagName,
        rt.TagPath || t2.TagName,
        rt.Level + 1
    from Tags t2
    join RecursiveTagHierarchy rt on t2.Id > rt.Id
    where rt.Level < 3 and t2.IsModeratorOnly = 0
),
UserPostStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        coalesce(sum(p.Score), 0) as TotalPostScore,
        max(p.LastActivityDate) as LastActivity,
        -- Compute average title length of questions, safely ignoring null titles
        avg(char_length(coalesce(p.Title, ''))) filter (where p.PostTypeId = 1) as AvgQuestionTitleLength,
        -- Extract domain from WebsiteUrl
        substring(u.WebsiteUrl from 'https?://([^/]+)') as WebsiteDomain,
        -- Number of badges by class
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        -- User reputation rank using window function
        rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.WebsiteUrl
),
AcceptedAnswerDetails as (
    select
        q.Id as QuestionId,
        a.Id as AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.CreationDate as AcceptedAnswerCreation,
        u.Id as AnswererUserId,
        u.DisplayName as AnswererName,
        u.Reputation as AnswererReputation,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as rn
    from Posts q
    join Posts a on a.Id = q.AcceptedAnswerId and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
TopCommentsForQuestions as (
    select
        c.PostId,
        c.Id as CommentId,
        c.Score,
        c.Text,
        c.CreationDate,
        c.UserId,
        row_number() over (partition by c.PostId order by c.Score desc nulls last, c.CreationDate asc) as rn
    from Comments c
    where exists (
        select 1 from Posts p where p.Id = c.PostId and p.PostTypeId = 1
    )
),
PostLinkSummary as (
    select 
        p.Id as PostId,
        count(pl.Id) filter (where pl.LinkTypeId = 1) as LinkedCount,
        count(pl.Id) filter (where pl.LinkTypeId = 3) as DuplicateCount
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id
    group by p.Id
),
UserVoteSummary as (
    select
        v.UserId,
        count(*) filter (where v.VoteTypeId = 2) as UpVotesCast,
        count(*) filter (where v.VoteTypeId = 3) as DownVotesCast,
        count(distinct v.PostId) as DistinctPostsVotedOn
    from Votes v
    where v.UserId is not null
    group by v.UserId
)
select 
    ups.UserId,
    ups.DisplayName,
    ups.QuestionsCount,
    ups.AnswersCount,
    ups.TotalPostScore,
    ups.ReputationRank,
    ups.AvgQuestionTitleLength,
    ups.WebsiteDomain,
    ups.GoldBadges,
    ups.SilverBadges,
    ups.BronzeBadges,
    uvs.UpVotesCast,
    uvs.DownVotesCast,
    uvs.DistinctPostsVotedOn,
    -- Fetch accepted answer details for user's questions using lateral join (correlated subquery)
    coalesce(accepted.AcceptedAnswerId, -1) as AcceptedAnswerId,
    accepted.AcceptedAnswerScore,
    accepted.AnswererName,
    accepted.AnswererReputation,
    pl.LinkedCount,
    pl.DuplicateCount,
    -- Aggregate most frequent tags among user's questions (complex string aggregation)
    (select string_agg(rt.TagName, ', ' order by count(*) desc) 
     from RecursiveTagHierarchy rt
     join Posts pq on pq.OwnerUserId = ups.UserId and pq.PostTypeId = 1 and pq.Tags like ('%<' || rt.TagName || '>%')
     group by rt.Level limit 3) as TopUserTags,
    -- Boolean logic combining badges and votes
    case 
        when ups.GoldBadges > 0 and uvs.UpVotesCast > uvs.DownVotesCast then 'High Impact User'
        when ups.SilverBadges > 5 or ups.AnswersCount > ups.QuestionsCount then 'Active Contributor'
        else 'Regular User'
    end as UserCategory
from UserPostStats ups
left join UserVoteSummary uvs on uvs.UserId = ups.UserId
left join AcceptedAnswerDetails accepted on accepted.QuestionId in (
    select p.Id from Posts p where p.OwnerUserId = ups.UserId and p.PostTypeId = 1
)
left join PostLinkSummary pl on pl.PostId in (
    select p.Id from Posts p where p.OwnerUserId = ups.UserId and p.PostTypeId = 1
)
where ups.QuestionsCount > 0 or ups.AnswersCount > 0
order by ups.ReputationRank, ups.TotalPostScore desc
limit 100;