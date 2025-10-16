-- {"query": "305.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2000} 
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
        t.Id,
        t.TagName,
        t.Count,
        r.Level + 1,
        r.Path || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> r.Id and t.Count < r.Count and not t.TagName = any(r.Path)
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
        coalesce(ubc_gold.BadgeCount,0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount,0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount,0) as BronzeBadges,
        row_number() over (order by u.Reputation desc) as RepRank
    from Users u
    left join UserBadgeCounts ubc_gold on ubc_gold.UserId = u.Id and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on ubc_silver.UserId = u.Id and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on ubc_bronze.UserId = u.Id and ubc_bronze.Class = 3
),
TopQuestions as (
    select
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        u.DisplayName as OwnerName,
        count(c.Id) as CommentCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes
    from Posts p
    left join Comments c on c.PostId = p.Id
    left join Votes v on v.PostId = p.Id
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
    group by p.Id, p.OwnerUserId, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.AcceptedAnswerId, u.DisplayName
    having p.Score > 10 and p.ViewCount > 1000
),
AcceptedAnswersWithScores as (
    select
        a.Id,
        a.ParentId,
        a.Score,
        a.CreationDate,
        u.DisplayName as AnswerOwnerName
    from Posts a
    left join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
),
QuestionsWithAcceptedAnswerDetails as (
    select
        q.*,
        aa.Score as AcceptedAnswerScore,
        aa.CreationDate as AcceptedAnswerCreationDate,
        aa.AnswerOwnerName
    from TopQuestions q
    left join AcceptedAnswersWithScores aa on aa.Id = q.AcceptedAnswerId
),
RankedAnswers as (
    select
        a.ParentId as QuestionId,
        a.Id as AnswerId,
        a.Score,
        a.CreationDate,
        u.DisplayName as AnswerOwnerName,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    left join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
),
Top3AnswersPerQuestion as (
    select
        ra.QuestionId,
        ra.AnswerId,
        ra.Score,
        ra.CreationDate,
        ra.AnswerOwnerName
    from RankedAnswers ra
    where ra.AnswerRank <= 3
),
PostHistoryCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
),
QuestionsWithCloseInfo as (
    select
        q.*,
        phcr.CloseReasonName,
        phcr.CloseDate
    from QuestionsWithAcceptedAnswerDetails q
    left join PostHistoryCloseReasons phcr on phcr.PostId = q.Id
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesGiven,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesGiven,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),
UserActivityRanked as (
    select
        uas.*,
        rank() over (order by uas.QuestionCount desc, uas.AnswerCount desc, uas.CommentCount desc) as ActivityRank
    from UserActivitySummary uas
),
CombinedResults as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        q.OwnerUserId,
        q.OwnerName,
        q.AcceptedAnswerId,
        q.AcceptedAnswerScore,
        q.AcceptedAnswerCreationDate,
        q.AnswerOwnerName as AcceptedAnswerOwnerName,
        q.CloseReasonName,
        q.CloseDate,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.CommentCount,
        ua.UpVotesGiven,
        ua.DownVotesGiven,
        ua.LastPostDate,
        ua.ActivityRank,
        string_agg(distinct rth.TagName, ',' order by rth.TagName) as RelatedTags,
        string_agg(distinct t3.AnswerOwnerName || ' (Score: ' || t3.Score || ')', '; ' order by t3.Score desc) as Top3AnswersSummary
    from QuestionsWithCloseInfo q
    left join UserActivityRanked ua on ua.UserId = q.OwnerUserId
    left join RecursiveTagHierarchy rth on rth.TagName = any(string_to_array(substring(q.Tags from 2 for char_length(q.Tags)-2), '><'))
    left join Top3AnswersPerQuestion t3 on t3.QuestionId = q.Id
    group by
        q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.Tags, q.OwnerUserId, q.OwnerName, q.AcceptedAnswerId,
        q.AcceptedAnswerScore, q.AcceptedAnswerCreationDate, q.AnswerOwnerName, q.CloseReasonName, q.CloseDate,
        ua.QuestionCount, ua.AnswerCount, ua.CommentCount, ua.UpVotesGiven, ua.DownVotesGiven, ua.LastPostDate, ua.ActivityRank
)
select
    cr.QuestionId,
    cr.Title,
    cr.QuestionCreationDate,
    cr.QuestionScore,
    cr.ViewCount,
    cr.Tags,
    cr.OwnerUserId,
    cr.OwnerName,
    cr.AcceptedAnswerId,
    cr.AcceptedAnswerScore,
    cr.AcceptedAnswerCreationDate,
    cr.AcceptedAnswerOwnerName,
    cr.CloseReasonName,
    cr.CloseDate,
    cr.QuestionCount,
    cr.AnswerCount,
    cr.CommentCount,
    cr.UpVotesGiven,
    cr.DownVotesGiven,
    cr.LastPostDate,
    cr.ActivityRank,
    cr.RelatedTags,
    cr.Top3AnswersSummary,
    case
        when cr.CloseDate is not null then 'Closed'
        when cr.AcceptedAnswerId is not null then 'Answered'
        else 'Open'
    end as QuestionStatus,
    length(cr.Title) as TitleLength,
    coalesce(nullif(cr.Tags, ''), '<no-tags>') as TagsOrDefault,
    (select count(*) from Votes v where v.PostId = cr.QuestionId and v.VoteTypeId = 2) as TotalUpVotes,
    (select count(*) from Votes v where v.PostId = cr.QuestionId and v.VoteTypeId = 3) as TotalDownVotes,
    (select count(*) from Comments c where c.PostId = cr.QuestionId) as TotalComments,
    (select max(ph.CreationDate) from PostHistory ph where ph.PostId = cr.QuestionId) as LastHistoryEditDate
from CombinedResults cr
where cr.ActivityRank <= 100
order by cr.QuestionScore desc, cr.ViewCount desc, cr.QuestionCreationDate desc
limit 50;