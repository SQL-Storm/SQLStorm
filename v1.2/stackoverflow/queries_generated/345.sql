-- {"query": "345.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1624} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.ViewCount, 0) as ViewCount,
        coalesce(p.Score, 0) as Score,
        row_number() over (order by t.Count desc, t.TagName) as TagRank
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    where t.TagName is not null
),
UserBadgeSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostActivityWindow as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        count(c.Id) as CommentCount,
        sum(v.VoteTypeId = 2::int) as UpVotes,
        sum(v.VoteTypeId = 3::int) as DownVotes,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank,
        lag(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as NextScore
    from Posts p
    left join Comments c on c.PostId = p.Id
    left join Votes v on v.PostId = p.Id
    where p.PostTypeId in (1, 2)
    group by p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, p.Title, p.Tags
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title as QuestionTitle,
        q.OwnerUserId as QuestionOwner,
        count(a.Id) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        min(a.Score) as MinAnswerScore,
        sum(case when a.Score > q.Score then 1 else 0 end) as AnswersBetterThanQuestion,
        (select count(*) from Votes v where v.PostId = q.Id and v.VoteTypeId = 2) as QuestionUpvotes,
        (select count(*) from Votes v where v.PostId = q.Id and v.VoteTypeId = 3) as QuestionDownvotes,
        (select count(*) from Votes v where v.PostId in (select a2.Id from Posts a2 where a2.ParentId = q.Id) and v.VoteTypeId = 2) as AnswersUpvotes,
        (select count(*) from Votes v where v.PostId in (select a2.Id from Posts a2 where a2.ParentId = q.Id) and v.VoteTypeId = 3) as AnswersDownvotes
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId, q.Score
),
DuplicateLinkCounts as (
    select
        pl.PostId,
        count(pl.Id) filter (where pl.LinkTypeId = 3) as DuplicateCount,
        count(pl.Id) filter (where pl.LinkTypeId = 1) as LinkedCount
    from PostLinks pl
    group by pl.PostId
),
UserActivity as (
    select
        u.Id,
        u.DisplayName,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(c.Id) as CommentsMade,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotesCast,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotesCast,
        max(p.CreationDate) as LastPostDate,
        max(c.CreationDate) as LastCommentDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
)
select
    qas.QuestionId,
    qas.QuestionTitle,
    u.DisplayName as QuestionOwnerName,
    qas.AnswerCount,
    qas.AvgAnswerScore,
    qas.MaxAnswerScore,
    qas.MinAnswerScore,
    qas.AnswersBetterThanQuestion,
    qas.QuestionUpvotes,
    qas.QuestionDownvotes,
    qas.AnswersUpvotes,
    qas.AnswersDownvotes,
    coalesce(dl.DuplicateCount, 0) as DuplicateLinks,
    coalesce(dl.LinkedCount, 0) as LinkedPosts,
    rtc.TagName,
    rtc.Count as TagUsageCount,
    rtw.TagRank,
    uact.QuestionsPosted,
    uact.AnswersPosted,
    uact.CommentsMade,
    uact.UpVotesCast,
    uact.DownVotesCast,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.TagBasedBadges,
    case
        when qas.AnswerCount = 0 then 'Unanswered'
        when qas.AnswersBetterThanQuestion > 0 then 'Better Answers Exist'
        else 'No Better Answers'
    end as AnswerQualityStatus,
    case
        when qas.QuestionUpvotes > qas.QuestionDownvotes then 'Positive Question Sentiment'
        when qas.QuestionUpvotes < qas.QuestionDownvotes then 'Negative Question Sentiment'
        else 'Neutral Question Sentiment'
    end as QuestionSentiment,
    case
        when uact.LastPostDate is null and uact.LastCommentDate is null then 'Inactive User'
        when uact.LastPostDate > uact.LastCommentDate then 'Active Poster'
        else 'Active Commenter'
    end as UserActivityType
from QuestionAnswerStats qas
inner join Users u on u.Id = qas.QuestionOwner
left join DuplicateLinkCounts dl on dl.PostId = qas.QuestionId
left join RecursiveTagCounts rtc on rtc.TagName = substring(qas.QuestionTitle from '<([^>]+)>') -- crude tag extraction from title
left join RecursiveTagCounts rtw on rtw.Id = rtc.Id
left join UserActivity uact on uact.Id = u.Id
left join UserBadgeSummary ubs on ubs.UserId = u.Id
where qas.AnswerCount > 0
  and (u.Reputation > 1000 or ubs.GoldBadges > 0)
  and (rtc.Count > 100 or rtc.Count is null)
order by qas.AnswerCount desc, qas.MaxAnswerScore desc, u.Reputation desc
limit 100;