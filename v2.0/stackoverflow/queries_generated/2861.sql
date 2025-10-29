-- {"query": "2861.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1465} 
with RecursiveTagHierarchy as (
    select t.Id, t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, t.IsModeratorOnly, t.IsRequired, 0 as Level
    from Tags t
    where t.IsRequired = 1

    union all

    select t2.Id, t2.TagName, t2.Count, t2.ExcerptPostId, t2.WikiPostId, t2.IsModeratorOnly, t2.IsRequired, r.Level + 1
    from Tags t2
    join RecursiveTagHierarchy r on t2.IsRequired = 0 and t2.Count < r.Count
    where r.Level < 3
),
UserActivity AS (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1 and p.OwnerUserId = u.Id) as QuestionCount,
        count(distinct p2.Id) filter (where p2.PostTypeId = 2 and p2.OwnerUserId = u.Id) as AnswerCount,
        coalesce(sum(vUp.VoteCount),0) as TotalUpVotes,
        coalesce(sum(vDown.VoteCount),0) as TotalDownVotes,
        coalesce(badgeCounts.GoldBadges,0) as GoldBadges,
        coalesce(badgeCounts.SilverBadges,0) as SilverBadges,
        coalesce(badgeCounts.BronzeBadges,0) as BronzeBadges,
        row_number() over (order by count(distinct p.Id) filter (where p.PostTypeId = 1 and p.OwnerUserId = u.Id) desc) as QuestionRank,
        row_number() over (order by count(distinct p2.Id) filter (where p2.PostTypeId = 2 and p2.OwnerUserId = u.Id) desc) as AnswerRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Posts p2 on p2.OwnerUserId = u.Id
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        where VoteTypeId = 2
        group by PostId
    ) vUp on vUp.PostId = p.Id
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        where VoteTypeId = 3
        group by PostId
    ) vDown on vDown.PostId = p.Id
    left join (
        select UserId,
            sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
            sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
            sum(case when Class = 3 then 1 else 0 end) as BronzeBadges
        from Badges
        group by UserId
    ) badgeCounts on badgeCounts.UserId = u.Id
    group by u.Id, u.DisplayName, badgeCounts.GoldBadges, badgeCounts.SilverBadges, badgeCounts.BronzeBadges
),
PostWithCommentsAndVotes AS (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        count(distinct c.Id) as CommentCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVoteCount,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVoteCount,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as CloseDate,
        bool_or(ph.PostHistoryTypeId = 6) filter (where ph.UserId is not null) as HasBounty,
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last) as PostScoreRank
    from Posts p
    left join Comments c on c.PostId = p.Id
    left join Votes v on v.PostId = p.Id
    left join PostHistory ph on ph.PostId = p.Id
    group by p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.Title, p.Tags, p.OwnerUserId, p.AcceptedAnswerId
),
CorrelatedAnswers AS (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score as AnswerScore,
        u.DisplayName as AnswerOwner,
        (
            select avg(v2.Score)
            from Posts v2
            where v2.PostTypeId = 2 and v2.OwnerUserId = a.OwnerUserId
        ) as AverageUserAnswerScore,
        rank() over (partition by a.ParentId order by a.Score desc) as AnswerRankForQuestion
    from Posts a
    join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
)
select
    ua.UserId,
    ua.DisplayName,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalUpVotes - ua.TotalDownVotes as NetVotes,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    p.CommentCount,
    p.UpVoteCount,
    p.DownVoteCount,
    p.HasBounty,
    p.PostScoreRank,
    a.AnswerId,
    a.AnswerScore,
    a.AverageUserAnswerScore,
    a.AnswerRankForQuestion,
    coalesce(rth.Level, -1) as TagHierarchyLevel,
    coalesce(rth.TagName, 'NoTag') as TagName,
    case
        when p.CloseDate is not null then 'Closed'
        when p.HasBounty then 'Bountied'
        else 'Open'
    end as PostStatus,
    substring(p.Title from 1 for 50) || 
        case when length(p.Title) > 50 then '...' else '' end as ShortTitle,
    regexp_replace(coalesce(p.Tags, ''), '[<>]', ',') as TagsAsCSV,
    coalesce(ua.AnswerRank, 99999) as UserAnswerRank,
    coalesce(ua.QuestionRank, 99999) as UserQuestionRank
from UserActivity ua
left join PostWithCommentsAndVotes p on p.OwnerUserId = ua.UserId and p.PostTypeId = 1
left join CorrelatedAnswers a on a.QuestionId = p.PostId
left join RecursiveTagHierarchy rth on rth.TagName = any(string_to_array(coalesce(p.Tags, ''), '><'))
where ua.QuestionCount > 5 and p.Score > 0 and a.AnswerRankForQuestion <= 3
order by ua.NetVotes desc, p.Score desc, a.AnswerScore desc
limit 100;