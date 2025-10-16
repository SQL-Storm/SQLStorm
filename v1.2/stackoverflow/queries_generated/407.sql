-- {"query": "407.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1925} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(u.Location, 'Unknown') as Location,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct b.Id) as BadgeCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesReceived,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesReceived,
        row_number() over (partition by coalesce(u.Location, 'Unknown') order by u.Reputation desc) as LocationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, coalesce(u.Location, 'Unknown')
),
TopUsers as (
    select * from RecursiveUserActivity
    where LocationRank <= 5
),
QuestionStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        coalesce(p.AcceptedAnswerId, -1) as AcceptedAnswerId,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
        row_number() over (order by p.Score desc, p.ViewCount desc) as RankByScoreView
    from Posts p
    where p.PostTypeId = 1
),
AnswerStats as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.CreationDate,
        a.Score,
        a.OwnerUserId,
        (select count(*) from Comments c where c.PostId = a.Id) as CommentCount,
        (select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 3) as DownVotes
    from Posts a
    where a.PostTypeId = 2
),
QuestionAnswerAggregates as (
    select
        q.QuestionId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        q.OwnerUserId as QuestionOwner,
        q.AcceptedAnswerId,
        count(a.AnswerId) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        sum(a.UpVotes) as TotalAnswerUpVotes,
        sum(a.DownVotes) as TotalAnswerDownVotes,
        max(case when a.AnswerId = q.AcceptedAnswerId then a.Score else null end) as AcceptedAnswerScore
    from QuestionStats q
    left join AnswerStats a on a.QuestionId = q.QuestionId
    group by q.QuestionId, q.Title, q.CreationDate, q.Score, q.ViewCount, q.Tags, q.OwnerUserId, q.AcceptedAnswerId
),
UserBadgeSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(b.Id) as TotalBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        pl.CreationDate,
        lt.Name as LinkTypeName
    from PostLinks pl
    inner join Posts p1 on p1.Id = pl.PostId
    inner join Posts p2 on p2.Id = pl.RelatedPostId
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId
    where pl.LinkTypeId = 3
),
RecentEdits as (
    select
        ph.PostId,
        ph.PostHistoryTypeId,
        p.Title,
        ph.CreationDate,
        ph.UserId,
        u.DisplayName as EditorName,
        ph.Comment,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as EditRank
    from PostHistory ph
    left join Posts p on p.Id = ph.PostId
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId in (4,5,6) -- Edit Title, Edit Body, Edit Tags
),
TopRecentEdits as (
    select * from RecentEdits where EditRank <= 3
),
TagUsage as (
    select
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as TagName,
        count(*) as UsageCount
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
    group by TagName
),
TopTags as (
    select TagName, UsageCount
    from TagUsage
    order by UsageCount desc
    limit 10
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
)
select
    t.Location,
    t.DisplayName as TopUserDisplayName,
    t.Reputation,
    t.QuestionCount,
    t.AnswerCount,
    t.BadgeCount,
    t.UpVotesReceived,
    t.DownVotesReceived,
    qa.QuestionId,
    qa.Title as QuestionTitle,
    qa.QuestionScore,
    qa.ViewCount as QuestionViews,
    qa.AnswerCount as NumAnswers,
    qa.MaxAnswerScore,
    qa.AvgAnswerScore,
    qa.TotalAnswerUpVotes,
    qa.TotalAnswerDownVotes,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    dl.PostId as DuplicatePostId,
    dl.RelatedPostId as DuplicateRelatedPostId,
    dl.PostTitle as DuplicatePostTitle,
    dl.RelatedPostTitle as DuplicateRelatedPostTitle,
    dl.CreationDate as DuplicateLinkDate,
    dl.LinkTypeName as DuplicateLinkType,
    tre.PostId as EditedPostId,
    tre.PostHistoryTypeId as EditType,
    tre.Title as EditedPostTitle,
    tre.CreationDate as EditDate,
    tre.EditorName,
    tre.Comment as EditComment,
    tt.TagName as PopularTag,
    tt.UsageCount as TagUsageCount,
    uas.QuestionsPosted,
    uas.AnswersPosted,
    uas.CommentsMade,
    uas.UpVotesGiven,
    uas.DownVotesGiven,
    uas.BadgesEarned
from TopUsers t
left join QuestionAnswerAggregates qa on qa.QuestionOwner = t.UserId
left join UserBadgeSummary ubs on ubs.UserId = t.UserId
left join DuplicateLinks dl on dl.PostId = qa.QuestionId
left join TopRecentEdits tre on tre.PostId = qa.QuestionId
left join TopTags tt on true
left join UserActivitySummary uas on uas.UserId = t.UserId
where qa.RankByScoreView <= 10
order by t.Location, t.Reputation desc, qa.QuestionScore desc, qa.ViewCount desc
limit 100;