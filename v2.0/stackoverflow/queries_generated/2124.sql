-- {"query": "2124.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1370} 
with RecursiveTagHierarchy as (
    select 
        t.Id, 
        t.TagName, 
        1 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select 
        child.Id,
        child.TagName,
        r.Level + 1,
        r.Path || child.Id
    from Tags child
    join RecursiveTagHierarchy r on child.ExcerptPostId = r.Id
    where not child.Id = any(r.Path) and r.Level < 3
),
PostRankedScores as (
    select 
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        p.ViewCount,
        u.Reputation,
        dense_rank() over (
            partition by p.PostTypeId order by p.Score desc, p.ViewCount desc, p.CreationDate asc
        ) as ScoreRank
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId in (1,2) and p.Score is not null
),
BadgeRankings as (
    select 
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        count(*) over (partition by b.UserId) as BadgeCount,
        row_number() over (partition by b.UserId order by b.Date desc) as RecentBadgeRank
    from Badges b
    where b.Class in (1, 2, 3)
),
UserAggregates as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        coalesce(sum(vtUp.CountUpVotes), 0) as TotalUpVotesReceived,
        coalesce(sum(vtDown.CountDownVotes), 0) as TotalDownVotesReceived,
        count(distinct b.Id) as TotalBadges,
        max(b.Date) as LastBadgeDate,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId in (10, 11)) as CloseReopenEvents
    from Users u
    left join Badges b on b.UserId = u.Id
    left join (
        select p.OwnerUserId, count(v.Id) as CountUpVotes
        from Votes v
        join Posts p on p.Id = v.PostId and p.OwnerUserId is not null
        where v.VoteTypeId = 2
        group by p.OwnerUserId
    ) vtUp on vtUp.OwnerUserId = u.Id
    left join (
        select p.OwnerUserId, count(v.Id) as CountDownVotes
        from Votes v
        join Posts p on p.Id = v.PostId and p.OwnerUserId is not null
        where v.VoteTypeId = 3
        group by p.OwnerUserId
    ) vtDown on vtDown.OwnerUserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, vtUp.CountUpVotes, vtDown.CountDownVotes
),
PostsWithDuplicateCount as (
    select 
        p.Id, p.PostTypeId, p.Title, p.OwnerUserId, p.Score, p.ViewCount, p.CreationDate,
        coalesce(CountLinks.DuplicateCount, 0) as DuplicateLinksCount
    from Posts p
    left join (
        select PostId, count(*) as DuplicateCount
        from PostLinks
        where LinkTypeId = 3
        group by PostId
    ) CountLinks on p.Id = CountLinks.PostId
    where p.PostTypeId = 1
),
RankedAnswers as (
    select
        a.Id,
        a.ParentId,
        a.Score,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerScoreRank
    from Posts a
    where a.PostTypeId = 2
),
AcceptedAnswersWithScoreDiff as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Score as QuestionScore,
        aa.Id as AcceptedAnswerId,
        aa.Score as AcceptedAnswerScore,
        aa.Score - q.Score as ScoreDifference
    from Posts q
    left join Posts aa on q.AcceptedAnswerId = aa.Id
    where q.PostTypeId = 1
)
select
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.TotalUpVotesReceived,
    u.TotalDownVotesReceived,
    u.TotalBadges,
    u.LastBadgeDate,
    u.CloseReopenEvents,
    p.Title as TopQuestionTitle,
    p.Score as QuestionScore,
    p.ViewCount as QuestionViews,
    p.DuplicateLinksCount,
    aa.AcceptedAnswerId,
    aa.AcceptedAnswerScore,
    aa.ScoreDifference,
    string_agg(distinct rt.TagName, ', ' order by rt.Level) as RecursiveTags,
    string_agg(distinct br.BadgeName, ', ' order by br.Class, br.Date desc) as RecentBadges
from UserAggregates u
left join PostsWithDuplicateCount p on p.OwnerUserId = u.UserId
    and p.Score = (
        select max(Score) from PostsWithDuplicateCount p2 where p2.OwnerUserId = u.UserId and p2.PostTypeId = 1
    )
left join AcceptedAnswersWithScoreDiff aa on aa.QuestionId = p.Id
left join RecursiveTagHierarchy rt on p.Tags like '%' || rt.TagName || '%'
left join (
    select b.UserId, b.Name as BadgeName, b.Class, b.Date
    from Badges b
    where b.Class in (1, 2, 3)
) br on br.UserId = u.UserId
group by 
    u.UserId, u.DisplayName, u.Reputation, u.TotalUpVotesReceived, u.TotalDownVotesReceived, u.TotalBadges, u.LastBadgeDate, u.CloseReopenEvents,
    p.Title, p.Score, p.ViewCount, p.DuplicateLinksCount,
    aa.AcceptedAnswerId, aa.AcceptedAnswerScore, aa.ScoreDifference
having 
    (u.TotalUpVotesReceived + u.TotalDownVotesReceived) > 1000
order by u.Reputation desc, u.TotalBadges desc, p.Score desc
limit 100;