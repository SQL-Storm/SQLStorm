-- {"query": "263.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1757} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        t2.Id,
        t2.TagName,
        t2.Count,
        r.Level + 1,
        r.Path || t2.TagName
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id > r.Id and t2.IsModeratorOnly = 0 and t2.IsRequired = 0
    where r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        row_number() over (order by u.Reputation desc) as RepRank,
        avg(u.Reputation) over () as AvgReputation,
        max(u.Reputation) over () as MaxReputation
    from Users u
),
PostAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount,
        count(a.Id) as AnswerCount,
        coalesce(sum(a.Score),0) as TotalAnswerScore,
        max(a.Score) as MaxAnswerScore,
        min(a.Score) as MinAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        bool_or(a.OwnerUserId is null) as HasAnonymousAnswers
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount
),
PostWithCloseInfo as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ClosedDate,
        crt.Name as CloseReasonName,
        ph.Comment as CloseReasonId,
        ph.CreationDate as CloseVoteDate
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where p.PostTypeId = 1
),
TopVotedAnswers as (
    select
        a.Id,
        a.ParentId as QuestionId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        u.DisplayName as AnswerOwnerName,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    left join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesGiven,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesGiven,
        count(distinct b.Id) as BadgesEarned
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
ComplexFilteredPosts as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        array_length(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><'), 1) as TagCount,
        case when p.ClosedDate is not null then 1 else 0 end as IsClosed,
        coalesce(crt.Name, 'Open') as CloseReason,
        (select count(*) from Comments c where c.PostId = p.Id and c.Score > 0) as PositiveCommentCount,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVoteCount,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVoteCount
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where p.PostTypeId in (1,2)
),
CombinedResults as (
    select
        p.Id as PostId,
        p.Title,
        p.OwnerName,
        p.Score,
        p.ViewCount,
        p.TagCount,
        p.IsClosed,
        p.CloseReason,
        p.PositiveCommentCount,
        p.UpVoteCount,
        p.DownVoteCount,
        u.QuestionsPosted,
        u.AnswersPosted,
        u.CommentsMade,
        u.UpVotesGiven,
        u.DownVotesGiven,
        u.BadgesEarned,
        r.RepRank,
        r.AvgReputation,
        r.MaxReputation,
        row_number() over (partition by p.IsClosed order by p.Score desc, p.ViewCount desc) as RankWithinStatus
    from ComplexFilteredPosts p
    left join UserActivitySummary u on u.UserId = p.OwnerUserId
    left join UserReputationWindow r on r.Id = p.OwnerUserId
    where p.TagCount > 2 and (p.IsClosed = 0 or (p.IsClosed = 1 and p.UpVoteCount > 5))
)
select
    cr.PostId,
    cr.Title,
    cr.OwnerName,
    cr.Score,
    cr.ViewCount,
    cr.TagCount,
    cr.IsClosed,
    cr.CloseReason,
    cr.PositiveCommentCount,
    cr.UpVoteCount,
    cr.DownVoteCount,
    cr.QuestionsPosted,
    cr.AnswersPosted,
    cr.CommentsMade,
    cr.UpVotesGiven,
    cr.DownVotesGiven,
    cr.BadgesEarned,
    cr.RepRank,
    cr.AvgReputation,
    cr.MaxReputation,
    string_agg(distinct rth.TagName, ', ') as RelatedTags,
    case
        when cr.Score > cr.AvgReputation then 'Above Avg Score'
        when cr.Score = cr.AvgReputation then 'At Avg Score'
        else 'Below Avg Score'
    end as ScoreVsAvgReputation
from CombinedResults cr
left join RecursiveTagHierarchy rth on position(rth.TagName in cr.Title) > 0 or position(rth.TagName in coalesce(cr.CloseReason, '')) > 0
group by
    cr.PostId,
    cr.Title,
    cr.OwnerName,
    cr.Score,
    cr.ViewCount,
    cr.TagCount,
    cr.IsClosed,
    cr.CloseReason,
    cr.PositiveCommentCount,
    cr.UpVoteCount,
    cr.DownVoteCount,
    cr.QuestionsPosted,
    cr.AnswersPosted,
    cr.CommentsMade,
    cr.UpVotesGiven,
    cr.DownVotesGiven,
    cr.BadgesEarned,
    cr.RepRank,
    cr.AvgReputation,
    cr.MaxReputation
order by cr.IsClosed, cr.Score desc, cr.ViewCount desc
limit 100;