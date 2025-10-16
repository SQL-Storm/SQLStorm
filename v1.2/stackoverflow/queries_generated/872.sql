-- {"query": "872.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1799} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(u.Location, 'Unknown') as Location,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        count(b.Id) as BadgesEarned,
        max(b.Date) as LastBadgeDate,
        row_number() over (partition by coalesce(u.Location, 'Unknown') order by u.Reputation desc) as RepRankByLocation
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId in (1,2)
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, coalesce(u.Location, 'Unknown')
),
TopQuestionsPerUser as (
    select
        p.OwnerUserId as UserId,
        p.Id as QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        dense_rank() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as QuestionRank
    from Posts p
    where p.PostTypeId = 1 and p.Score is not null
),
UserAnswerStats as (
    select
        a.OwnerUserId as UserId,
        count(a.Id) as TotalAnswers,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        count(distinct a.ParentId) as DistinctQuestionsAnswered
    from Posts a
    where a.PostTypeId = 2
    group by a.OwnerUserId
),
UserVoteSummary as (
    select
        v.UserId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotesCast,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotesCast,
        sum(case when vt.Name = 'Close' then 1 else 0 end) as CloseVotesCast,
        sum(case when vt.Name = 'Reopen' then 1 else 0 end) as ReopenVotesCast
    from Votes v
    inner join VoteTypes vt on vt.Id = v.VoteTypeId
    where v.UserId is not null
    group by v.UserId
),
UserCommentActivity as (
    select
        c.UserId,
        count(c.Id) as CommentsCount,
        avg(length(c.Text)) as AvgCommentLength,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.UserId
),
UserEngagement as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.Location,
        ua.QuestionsAsked,
        coalesce(us.TotalAnswers,0) as AnswersGiven,
        ua.BadgesEarned,
        coalesce(uv.UpVotesCast,0) as UpVotesCast,
        coalesce(uv.DownVotesCast,0) as DownVotesCast,
        coalesce(uv.CloseVotesCast,0) as CloseVotesCast,
        coalesce(uv.ReopenVotesCast,0) as ReopenVotesCast,
        coalesce(uc.CommentsCount,0) as CommentsCount,
        round(coalesce(uc.AvgCommentLength,0),2) as AvgCommentLength,
        ua.RepRankByLocation
    from RecursiveUserActivity ua
    left join UserAnswerStats us on us.UserId = ua.UserId
    left join UserVoteSummary uv on uv.UserId = ua.UserId
    left join UserCommentActivity uc on uc.UserId = ua.UserId
),
FilteredUsers as (
    select * from UserEngagement
    where QuestionsAsked >= 10
      and AnswersGiven >= 5
      and BadgesEarned >= 3
      and Reputation >= 1000
      and RepRankByLocation <= 5
),
UserTopQuestions as (
    select
        tq.UserId,
        tq.QuestionId,
        tq.Title,
        tq.Score,
        tq.ViewCount,
        tq.AnswerCount
    from TopQuestionsPerUser tq
    inner join FilteredUsers fu on fu.UserId = tq.UserId
    where tq.QuestionRank <= 3
),
DuplicateLinksOnTopQuestions as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        pl.LinkTypeId,
        lt.Name as LinkTypeName,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId
    inner join Posts p1 on p1.Id = pl.PostId
    inner join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3 -- Duplicate
      and pl.PostId in (select QuestionId from UserTopQuestions)
),
LatestPostHistoryPerPost as (
    select distinct on (ph.PostId)
        ph.PostId,
        ph.Id as PostHistoryId,
        ph.PostHistoryTypeId,
        pht.Name as PostHistoryTypeName,
        ph.CreationDate as HistoryDate,
        ph.UserId as EditorUserId,
        ph.UserDisplayName as EditorDisplayName,
        ph.Comment,
        ph.Text
    from PostHistory ph
    inner join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    order by ph.PostId, ph.CreationDate desc
),
UserActivitySummary as (
    select
        fe.UserId,
        fe.DisplayName,
        count(distinct utq.QuestionId) as TopQuestionsCount,
        count(distinct dl.PostId) as DuplicateLinksCount,
        count(distinct lpp.PostId) as PostsEdited,
        max(lpp.HistoryDate) as LastEditDate,
        bool_or(lpp.PostHistoryTypeName = 'Post Closed') as HasClosedPosts
    from FilteredUsers fe
    left join UserTopQuestions utq on utq.UserId = fe.UserId
    left join DuplicateLinksOnTopQuestions dl on dl.PostId in (select QuestionId from UserTopQuestions where UserId = fe.UserId)
    left join LatestPostHistoryPerPost lpp on lpp.PostId in (select QuestionId from UserTopQuestions where UserId = fe.UserId)
    group by fe.UserId, fe.DisplayName
)
select
    uas.UserId,
    uas.DisplayName,
    fe.Location,
    fe.Reputation,
    fe.QuestionsAsked,
    fe.AnswersGiven,
    fe.BadgesEarned,
    fe.UpVotesCast,
    fe.DownVotesCast,
    fe.CloseVotesCast,
    fe.ReopenVotesCast,
    fe.CommentsCount,
    fe.AvgCommentLength,
    uas.TopQuestionsCount,
    uas.DuplicateLinksCount,
    uas.PostsEdited,
    uas.LastEditDate,
    uas.HasClosedPosts,
    string_agg(distinct t.TagName, ', ') within group (order by t.TagName) as UserQuestionTags,
    -- Complex predicate: ratio of answers to questions + comment activity index
    (case when fe.QuestionsAsked > 0 then round((fe.AnswersGiven::numeric / fe.QuestionsAsked) * (fe.CommentsCount + 1), 2) else null end) as EngagementIndex
from UserActivitySummary uas
inner join FilteredUsers fe on fe.UserId = uas.UserId
left join Posts p on p.OwnerUserId = fe.UserId and p.PostTypeId = 1
left join lateral (
    select unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as TagName
    limit 10
) t on true
group by
    uas.UserId, uas.DisplayName, fe.Location, fe.Reputation, fe.QuestionsAsked, fe.AnswersGiven, fe.BadgesEarned,
    fe.UpVotesCast, fe.DownVotesCast, fe.CloseVotesCast, fe.ReopenVotesCast,
    fe.CommentsCount, fe.AvgCommentLength,
    uas.TopQuestionsCount, uas.DuplicateLinksCount, uas.PostsEdited, uas.LastEditDate, uas.HasClosedPosts
order by EngagementIndex desc nulls last, fe.Reputation desc
limit 100;