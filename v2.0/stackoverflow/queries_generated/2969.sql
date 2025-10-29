-- {"query": "2969.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1342} 
with RecursiveBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Class,
        count(*) as BadgeCount
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName, b.Class
), TopUsersByBadge as (
    select
        UserId,
        DisplayName,
        coalesce(sum(case when Class = 1 then BadgeCount else 0 end),0) as GoldBadges,
        coalesce(sum(case when Class = 2 then BadgeCount else 0 end),0) as SilverBadges,
        coalesce(sum(case when Class = 3 then BadgeCount else 0 end),0) as BronzeBadges,
        coalesce(sum(BadgeCount),0) as TotalBadges
    from RecursiveBadgeCounts
    group by UserId, DisplayName
), LatestAnswers as (
    select
        p.Id as AnswerId,
        p.ParentId as QuestionId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        p.Body,
        row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank
    from Posts p
    where p.PostTypeId = 2
), QuestionStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId as AskerUserId,
        q.AcceptedAnswerId,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        coalesce(a.AnswerCount, 0) as AnswerCount,
        coalesce(c.CommentCount, 0) as CommentCount,
        case when q.ClosedDate is null then 0 else 1 end as IsClosed,
        (select count(*) from Votes v2 where v2.PostId = q.Id and v2.VoteTypeId = 2) as QuestionUpVotes,
        (select count(*) from Votes v2 where v2.PostId = q.Id and v2.VoteTypeId = 3) as QuestionDownVotes
    from Posts q
    left join (
        select ParentId, count(*) as AnswerCount
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) a on a.ParentId = q.Id
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) c on c.PostId = q.Id
    where q.PostTypeId = 1
), UserActivity AS (
    select
        u.Id,
        u.DisplayName,
        count(distinct ph.PostId) as Edits,
        count(distinct c.Id) as CommentsMade,
        count(distinct v.Id) as VotesCast
    from Users u
    left join PostHistory ph on ph.UserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
), LinkedDuplicatePairs as (
    select
        pl.PostId as OriginalPostId,
        pl.RelatedPostId as DuplicatePostId,
        p1.Title as OriginalTitle,
        p2.Title as DuplicateTitle
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3 -- duplicates
), AnswerWithRankedVotes as (
    select
        a.AnswerId,
        a.QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        dense_rank() over (partition by a.QuestionId order by a.Score desc) as VoteRank
    from LatestAnswers a
), HighScoreAnswers as (
    select distinct
        aw.AnswerId,
        aw.QuestionId,
        aw.OwnerUserId,
        aw.Score
    from AnswerWithRankedVotes aw
    where aw.VoteRank = 1
), UserBadgeSummary as (
    select
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by b.UserId order by b.Date desc) as BadgeRank
    from Badges b
), RecentBadgesTop3 as (
    select
        UserId,
        string_agg(BadgeName || ' (' || 
            case Class when 1 then 'Gold' when 2 then 'Silver' when 3 then 'Bronze' else 'Unknown' end || ')', ', ') as RecentBadgeList
    from UserBadgeSummary
    where BadgeRank <= 3
    group by UserId
)
select
    qs.QuestionId,
    qs.Title,
    qs.QuestionScore,
    qs.ViewCount,
    qs.AnswerCount,
    qs.CommentCount,
    qs.IsClosed,
    qs.QuestionUpVotes,
    qs.QuestionDownVotes,
    (select DisplayName from Users where Id = qs.AskerUserId) as AskerName,
    hu.DisplayName as HighestScoringAnswerer,
    hu.Id as HighestScoringAnswererId,
    hu.UserBadgeSummary,
    ua.Edits,
    ua.CommentsMade,
    ua.VotesCast,
    ld.OriginalTitle,
    ld.DuplicateTitle,
    array_to_string(array(
        select unnest(string_to_array(qs.Tags, '><'))
    ), ', ') as ParsedTags,
    case 
        when qs.IsClosed = 1 then 'Closed'
        when qs.AnswerCount = 0 then 'Unanswered'
        else 'Open'
    end as QuestionStatus
from QuestionStats qs
left join (
    select
        hsa.QuestionId,
        u.Id,
        u.DisplayName,
        coalesce(rb.RecentBadgeList, '') as UserBadgeSummary
    from HighScoreAnswers hsa
    join Users u on u.Id = hsa.OwnerUserId
    left join RecentBadgesTop3 rb on rb.UserId = u.Id
) hu on hu.QuestionId = qs.QuestionId
left join UserActivity ua on ua.Id = qs.AskerUserId
left join LinkedDuplicatePairs ld on ld.OriginalPostId = qs.QuestionId
where qs.QuestionScore > 10 and ua.Edits >= 1
order by qs.QuestionScore desc, qs.ViewCount desc
limit 50;