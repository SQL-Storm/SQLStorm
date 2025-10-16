-- {"query": "229.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1460} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(p.Score),0) as TotalPostScore,
        coalesce(sum(vt2.UpVotes),0) as TotalUpVotes,
        coalesce(sum(vt3.DownVotes),0) as TotalDownVotes,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select PostId, count(*) as UpVotes from Votes where VoteTypeId = 2 group by PostId
    ) vt2 on vt2.PostId = p.Id
    left join (
        select PostId, count(*) as DownVotes from Votes where VoteTypeId = 3 group by PostId
    ) vt3 on vt3.PostId = p.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
BadgeSummary as (
    select
        UserId,
        count(*) filter (where Class = 1) as GoldBadges,
        count(*) filter (where Class = 2) as SilverBadges,
        count(*) filter (where Class = 3) as BronzeBadges,
        count(distinct Name) as DistinctBadges
    from Badges
    group by UserId
),
TopQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as QuestionRank
    from Posts p
    where p.PostTypeId = 1
),
QuestionCloseInfo as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate else null end) as ClosedDate,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate else null end) as ReopenedDate,
        string_agg(distinct crt.Name, ', ') filter (where ph.PostHistoryTypeId = 10) as CloseReasons
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId in (10,11)
    group by ph.PostId
),
AnswerStats as (
    select
        p.ParentId as QuestionId,
        count(*) as AnswerCount,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore,
        sum(case when p.Id = q.AcceptedAnswerId then 1 else 0 end) as HasAcceptedAnswer
    from Posts p
    join Posts q on q.Id = p.ParentId and q.PostTypeId = 1
    where p.PostTypeId = 2
    group by p.ParentId
),
UserCommentStats as (
    select
        c.UserId,
        count(*) as CommentCount,
        avg(c.Score) as AvgCommentScore,
        max(c.Score) as MaxCommentScore
    from Comments c
    group by c.UserId
),
UserPostLinkStats as (
    select
        p.OwnerUserId,
        count(distinct pl.Id) filter (where lt.Name = 'Duplicate') as DuplicateLinks,
        count(distinct pl.Id) filter (where lt.Name = 'Linked') as LinkedPosts
    from PostLinks pl
    join Posts p on p.Id = pl.PostId
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by p.OwnerUserId
),
UserActivitySummary as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.TotalPostScore,
        bs.GoldBadges,
        bs.SilverBadges,
        bs.BronzeBadges,
        bs.DistinctBadges,
        coalesce(ucs.CommentCount,0) as CommentCount,
        coalesce(ucs.AvgCommentScore,0) as AvgCommentScore,
        coalesce(ucs.MaxCommentScore,0) as MaxCommentScore,
        coalesce(uls.DuplicateLinks,0) as DuplicateLinks,
        coalesce(uls.LinkedPosts,0) as LinkedPosts,
        ua.UserRank
    from RecursiveUserActivity ua
    left join BadgeSummary bs on bs.UserId = ua.UserId
    left join UserCommentStats ucs on ucs.UserId = ua.UserId
    left join UserPostLinkStats uls on uls.OwnerUserId = ua.UserId
),
TopUserQuestions as (
    select
        tq.*,
        qci.ClosedDate,
        qci.ReopenedDate,
        qci.CloseReasons,
        coalesce(ans.AnswerCount,0) as AnswerCount,
        coalesce(ans.AvgAnswerScore,0) as AvgAnswerScore,
        coalesce(ans.MaxAnswerScore,0) as MaxAnswerScore,
        coalesce(ans.HasAcceptedAnswer,0) as HasAcceptedAnswer
    from TopQuestions tq
    left join QuestionCloseInfo qci on qci.PostId = tq.Id
    left join AnswerStats ans on ans.QuestionId = tq.Id
    where tq.QuestionRank <= 5
)
select
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.TotalPostScore,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.BronzeBadges,
    uas.DistinctBadges,
    uas.CommentCount,
    uas.AvgCommentScore,
    uas.MaxCommentScore,
    uas.DuplicateLinks,
    uas.LinkedPosts,
    tq.Id as QuestionId,
    tq.Title,
    tq.CreationDate as QuestionCreationDate,
    tq.Score as QuestionScore,
    tq.ViewCount,
    tq.AnswerCount as QuestionAnswerCount,
    tq.FavoriteCount,
    tq.Tags,
    tq.ClosedDate,
    tq.ReopenedDate,
    tq.CloseReasons,
    tq.AvgAnswerScore,
    tq.MaxAnswerScore,
    tq.HasAcceptedAnswer,
    rank() over (partition by uas.UserId order by tq.Score desc, tq.ViewCount desc) as QuestionScoreRank
from UserActivitySummary uas
left join TopUserQuestions tq on tq.OwnerUserId = uas.UserId
where uas.UserRank <= 50
order by uas.UserRank, QuestionScoreRank
limit 200;