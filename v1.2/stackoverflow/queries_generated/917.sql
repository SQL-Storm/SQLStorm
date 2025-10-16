-- {"query": "917.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1264} 
with RecursiveBadgeCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        dense_rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
QuestionsWithAnswerStats as (
    select 
        p.Id as QuestionId, 
        p.Title, 
        p.CreationDate,
        p.ViewCount,
        p.Score,
        u.Id as OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        coalesce(ans.AnswerCount,0) as AnswerCount,
        coalesce(ans.TopAnswerScore,0) as TopAnswerScore,
        coalesce(latest.CommentCount,0) as LatestCommentCount,
        coalesce(closed.ClosedDate, null) as ClosedDate
    from Posts p
    join Users u on u.Id = p.OwnerUserId
    left join (
        select ParentId, count(*) as AnswerCount, max(Score) as TopAnswerScore
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) ans on ans.ParentId = p.Id
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        where CreationDate > now() - interval '30 days'
        group by PostId
    ) latest on latest.PostId = p.Id
    left join Posts closed on closed.Id = p.Id and closed.ClosedDate is not null
    where p.PostTypeId = 1
),
CloseReasonCounts as (
    select 
        cht.Name as CloseReason,
        count(distinct ph.PostId) as CloseCount
    from PostHistory ph
    join PostHistoryTypes chtt on chtt.Id = ph.PostHistoryTypeId
    join CloseReasonTypes cht on cht.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
    group by cht.Name
),
UserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        max(p.CreationDate) as LastPostDate,
        max(c.CreationDate) as LastCommentDate,
        count(distinct p.Id) as TotalPosts,
        count(distinct c.Id) as TotalComments,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as TotalUpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as TotalDownVotes
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),
AnswerSentimentScores as (
    select 
        p.Id as AnswerId,
        p.ParentId as QuestionId,
        p.Score,
        length(p.Body) as BodyLength,
        coalesce((select avg(Score) from Posts where ParentId = p.ParentId and Id != p.Id and PostTypeId = 2),0) as AvgSiblingAnswerScore,
        row_number() over (partition by p.ParentId order by p.Score desc) as RankByScore
    from Posts p
    where p.PostTypeId = 2
),
FinalResults as (
    select 
        q.QuestionId,
        q.Title,
        q.ViewCount,
        q.Score as QuestionScore,
        q.AnswerCount,
        q.TopAnswerScore,
        q.LatestCommentCount,
        case when q.ClosedDate is null then 'Open' else 'Closed' end as Status,
        r.CloseReason,
        r.CloseCount,
        u.DisplayName as OwnerName,
        u.Reputation,
        u.GoldBadges,
        u.SilverBadges,
        u.BronzeBadges,
        ua.TotalPosts,
        ua.TotalComments,
        ua.TotalUpVotes,
        ua.TotalDownVotes,
        ans.AnswerId,
        ans.BodyLength,
        ans.AvgSiblingAnswerScore,
        ans.RankByScore
    from QuestionsWithAnswerStats q
    left join CloseReasonCounts r on q.ClosedDate is not null
    left join RecursiveBadgeCounts u on u.UserId = q.OwnerUserId
    left join UserActivity ua on ua.UserId = q.OwnerUserId
    left join AnswerSentimentScores ans on ans.QuestionId = q.QuestionId and ans.RankByScore = 1
    where q.Score > 5
    and (
      (q.ClosedDate is null) 
      or 
      (r.CloseCount > 10)
    )
)
select 
    QuestionId,
    Title,
    concat('Views: ', ViewCount::text, ', Score: ', QuestionScore::text, ', Answers: ', AnswerCount::text) as QuestionSummary,
    Status,
    coalesce(CloseReason, 'N/A') as CloseReason,
    OwnerName,
    Reputation,
    concat('Badges (G/S/B): ', GoldBadges::text, '/', SilverBadges::text, '/', BronzeBadges::text) as BadgeSummary,
    concat('Posts: ', TotalPosts::text, ', Comments: ', TotalComments::text, ', UpVotes: ', TotalUpVotes::text, ', DownVotes: ', TotalDownVotes::text) as UserActivitySummary,
    AnswerId,
    BodyLength,
    AvgSiblingAnswerScore,
    RankByScore,
    row_number() over (partition by Status order by ViewCount desc) as RankWithinStatus
from FinalResults
where Title is not null
order by Status asc, RankWithinStatus asc
limit 50;