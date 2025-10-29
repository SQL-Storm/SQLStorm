-- {"query": "2451.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1241} 
with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        b.Date,
        row_number() over(partition by u.Id order by b.Date desc) as rn
    from Users u
    left join Badges b on u.Id = b.UserId
), RecentBadges as (
    select UserId, DisplayName, BadgeName, Class, Date
    from RecursiveUserBadges
    where rn <= 5
), PostScoresRanked as (
    select 
        p.Id, p.PostTypeId, p.OwnerUserId, p.Score, p.ViewCount, p.CreationDate,
        row_number() over(partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as rn,
        dense_rank() over(order by p.Score desc) as global_score_rank
    from Posts p
    where p.PostTypeId in (1,2)
), UserActivity as (
    select 
        u.Id as UserId,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        coalesce(sum(vtUp.CountUpVotes),0) as TotalUpVotes,
        coalesce(sum(vtDown.CountDownVotes),0) as TotalDownVotes,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    left join Comments c on u.Id = c.UserId
    left join (
        select PostId, count(*) as CountUpVotes
        from Votes v join VoteTypes vt on v.VoteTypeId = vt.Id and vt.Name = 'UpMod'
        group by PostId
    ) vtUp on vtUp.PostId = p.Id
    left join (
        select PostId, count(*) as CountDownVotes
        from Votes v join VoteTypes vt on v.VoteTypeId = vt.Id and vt.Name = 'DownMod'
        group by PostId
    ) vtDown on vtDown.PostId = p.Id
    group by u.Id
), DuplicateLinksCTE as (
    select 
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    where lt.Name = 'Duplicate'
), ComplexPosts as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        array_length(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><'),1) as TagCount,
        -- longest tag length example
        (
            select max(length(t)) from unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as t
        ) as MaxTagLength,
        p.OwnerUserId,
        p.CreationDate
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
), CorrelatedSubqueryScores as (
    select 
        p.Id,
        p.Score,
        (
            select avg(p2.Score) 
            from Posts p2 
            where p2.OwnerUserId = p.OwnerUserId and p2.Id <> p.Id and p2.Score is not null
        ) as AvgOtherPostsScore
    from Posts p
    where p.OwnerUserId is not null
), WindowedPostRanks as (
    select 
        p.OwnerUserId, p.Id, p.Score,
        rank() over (partition by p.OwnerUserId order by p.Score desc nulls last) as UserPostScoreRank,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as UserPostRecencyRank
    from Posts p
    where p.OwnerUserId is not null
)
select 
    u.Id as UserId,
    u.DisplayName,
    ua.QuestionsPosted,
    ua.AnswersPosted,
    ua.CommentsMade,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    ua.LastPostDate,
    rb.BadgeName, 
    rb.Class as BadgeClass,
    psr.Id as TopPostId,
    psr.Score as TopPostScore,
    psr.ViewCount as TopPostViewCount,
    cp.Title as SampleQuestionTitle,
    cp.TagCount as SampleQuestionTagCount,
    cp.MaxTagLength as SampleQuestionMaxTagLength,
    ds.AvgOtherPostsScore,
    dup.PostId as DuplicatePostId,
    dup.RelatedPostId as DuplicateOfPostId,
    dup.CreationDate as DuplicateLinkDate,
    dup.LinkTypeName as DuplicateLinkType,
    wpr.UserPostScoreRank,
    wpr.UserPostRecencyRank
from Users u
left join UserActivity ua on u.Id = ua.UserId
left join RecentBadges rb on u.Id = rb.UserId and rb.Date = (
    select max(Date) from RecentBadges r2 where r2.UserId = u.Id
)
left join PostScoresRanked psr on psr.OwnerUserId = u.Id and psr.rn = 1
left join ComplexPosts cp on cp.OwnerUserId = u.Id
left join CorrelatedSubqueryScores ds on ds.Id = psr.Id
left join DuplicateLinksCTE dup on dup.PostId = psr.Id
left join WindowedPostRanks wpr on wpr.Id = psr.Id
where u.Reputation > coalesce((select avg(Reputation) from Users),0)
order by u.Reputation desc, ua.TotalUpVotes desc
limit 100;