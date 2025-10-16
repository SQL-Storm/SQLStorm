-- {"query": "40.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1898} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        1 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsRequired = 1

    union all

    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        t2.IsModeratorOnly,
        t2.IsRequired,
        r.Level + 1,
        r.Path || t2.Id
    from Tags t2
    join RecursiveTagHierarchy r on t2.IsRequired = 1 and not t2.Id = any(r.Path)
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
UserReputationStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        coalesce(ubc_gold.BadgeCount, 0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount, 0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount, 0) as BronzeBadges,
        row_number() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join UserBadgeCounts ubc_gold on ubc_gold.UserId = u.Id and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on ubc_silver.UserId = u.Id and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on ubc_bronze.UserId = u.Id and ubc_bronze.Class = 3
),
PostAnswerStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score as QuestionScore,
        p.ViewCount,
        p.Tags,
        count(a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.OwnerUserId is null then 0 else 1 end) as AnswersWithOwner,
        sum(case when a.Score > 10 then 1 else 0 end) as HighScoreAnswers
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags
),
PostCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
),
TopQuestionsWithCloseInfo as (
    select
        pas.QuestionId,
        pas.Title,
        pas.OwnerUserId,
        pas.CreationDate,
        pas.QuestionScore,
        pas.ViewCount,
        pas.Tags,
        pas.AnswerCount,
        pas.MaxAnswerScore,
        pas.AvgAnswerScore,
        pas.AnswersWithOwner,
        pas.HighScoreAnswers,
        pcr.CloseReasonName,
        pcr.CloseDate,
        u.DisplayName as OwnerDisplayName,
        u.Reputation as OwnerReputation
    from PostAnswerStats pas
    left join PostCloseReasons pcr on pcr.PostId = pas.QuestionId
    left join Users u on u.Id = pas.OwnerUserId
    where pas.AnswerCount > 5 and pas.QuestionScore > 10
),
RankedComments as (
    select
        c.PostId,
        c.Id as CommentId,
        c.UserId,
        c.CreationDate,
        c.Score,
        c.Text,
        row_number() over (partition by c.PostId order by c.Score desc, c.CreationDate asc) as CommentRank
    from Comments c
),
TopCommentsPerQuestion as (
    select
        rc.PostId,
        rc.CommentId,
        rc.UserId,
        rc.CreationDate,
        rc.Score,
        rc.Text
    from RankedComments rc
    where rc.CommentRank <= 3
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesGiven,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesGiven,
        min(u.CreationDate) as UserSince,
        max(p.CreationDate) as LastPostDate,
        max(c.CreationDate) as LastCommentDate,
        max(v.CreationDate) as LastVoteDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
UserActivityRanked as (
    select
        ua.*,
        rank() over (order by ua.QuestionsPosted desc, ua.AnswersPosted desc, ua.CommentsMade desc) as ActivityRank
    from UserActivityWindow ua
),
CombinedResults as (
    select
        tq.QuestionId,
        tq.Title,
        tq.OwnerUserId,
        tq.OwnerDisplayName,
        tq.OwnerReputation,
        tq.CreationDate as QuestionCreationDate,
        tq.QuestionScore,
        tq.ViewCount,
        tq.Tags,
        tq.AnswerCount,
        tq.MaxAnswerScore,
        tq.AvgAnswerScore,
        tq.AnswersWithOwner,
        tq.HighScoreAnswers,
        tq.CloseReasonName,
        tq.CloseDate,
        tc.CommentId,
        tc.UserId as CommentUserId,
        tc.CreationDate as CommentCreationDate,
        tc.Score as CommentScore,
        tc.Text as CommentText,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.CommentsMade,
        ua.UpVotesGiven,
        ua.DownVotesGiven,
        ua.UserSince,
        ua.LastPostDate,
        ua.LastCommentDate,
        ua.LastVoteDate,
        ua.ActivityRank
    from TopQuestionsWithCloseInfo tq
    left join TopCommentsPerQuestion tc on tc.PostId = tq.QuestionId
    left join UserActivityRanked ua on ua.UserId = tc.UserId
)
select
    cr.*,
    case
        when cr.CloseReasonName is not null then 'Closed: ' || cr.CloseReasonName
        else 'Open'
    end as QuestionStatus,
    length(coalesce(cr.Tags, '')) - length(replace(coalesce(cr.Tags, ''), '><', '')) + 1 as TagCount,
    regexp_replace(coalesce(cr.Tags, ''), '[<>]', '', 'g') as CleanTags,
    coalesce(cr.CommentText, '') as SampleComment,
    coalesce(cr.DisplayName, 'Anonymous') as CommenterName,
    coalesce(cr.ActivityRank, 999999) as CommenterActivityRank,
    (select count(*) from PostLinks pl where pl.PostId = cr.QuestionId and pl.LinkTypeId = 1) as LinkedPostsCount,
    (select count(*) from PostLinks pl where pl.RelatedPostId = cr.QuestionId and pl.LinkTypeId = 3) as DuplicateCount,
    (select count(*) from Votes v where v.PostId = cr.QuestionId and v.VoteTypeId = 2) as QuestionUpVotes,
    (select count(*) from Votes v where v.PostId = cr.QuestionId and v.VoteTypeId = 3) as QuestionDownVotes,
    (select count(*) from Votes v where v.PostId in (select Id from Posts where ParentId = cr.QuestionId) and v.VoteTypeId = 2) as AnswersUpVotes,
    (select count(*) from Votes v where v.PostId in (select Id from Posts where ParentId = cr.QuestionId) and v.VoteTypeId = 3) as AnswersDownVotes
from CombinedResults cr
where cr.ActivityRank <= 100 or cr.ActivityRank is null
order by cr.QuestionScore desc, cr.AnswerCount desc, cr.CommentScore desc
limit 100;