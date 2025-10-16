-- {"query": "1.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2052} 
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
    where not t2.TagName = any(r.Path)
    and r.Level < 3
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
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        u.DisplayName as OwnerName,
        dense_rank() over (partition by p.OwnerUserId order by p.Score desc) as UserTopQuestionRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1 and p.Score > 10 and p.ClosedDate is null
),
AnswerStats as (
    select
        a.ParentId as QuestionId,
        count(*) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.OwnerUserId is null then 0 else 1 end) as AnsweredByRegisteredUsers
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
),
QuestionVotes as (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as Favorites
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
QuestionCommentsCount as (
    select
        c.PostId,
        count(*) as CommentCount
    from Comments c
    group by c.PostId
),
QuestionWithDetails as (
    select
        tq.Id,
        tq.Title,
        tq.OwnerUserId,
        tq.CreationDate,
        tq.Score,
        tq.ViewCount,
        tq.Tags,
        tq.AcceptedAnswerId,
        tq.OwnerName,
        as1.AnswerCount,
        as1.AvgAnswerScore,
        as1.MaxAnswerScore,
        as1.AnsweredByRegisteredUsers,
        qcr.CloseReason,
        qcr.CloseDate,
        qv.UpVotes,
        qv.DownVotes,
        qv.Favorites,
        coalesce(qc.CommentCount,0) as CommentCount
    from TopQuestions tq
    left join AnswerStats as1 on as1.QuestionId = tq.Id
    left join QuestionCloseReasons qcr on qcr.PostId = tq.Id
    left join QuestionVotes qv on qv.PostId = tq.Id
    left join QuestionCommentsCount qc on qc.PostId = tq.Id
),
RankedQuestions as (
    select
        qwd.*,
        row_number() over (partition by qwd.OwnerUserId order by qwd.Score desc, qwd.ViewCount desc) as UserQuestionRank,
        rank() over (order by qwd.Score desc, qwd.ViewCount desc) as GlobalRank
    from QuestionWithDetails qwd
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        count(distinct v.Id) filter (where vt.Name = 'UpMod') as UpVotesGiven,
        count(distinct v.Id) filter (where vt.Name = 'DownMod') as DownVotesGiven,
        max(p.CreationDate) as LastPostDate,
        max(c.CreationDate) as LastCommentDate,
        max(v.CreationDate) as LastVoteDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join VoteTypes vt on vt.Id = v.VoteTypeId
    group by u.Id, u.DisplayName
),
UserTopTags as (
    select
        p.OwnerUserId as UserId,
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as Tag,
        count(*) as TagCount
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
    group by p.OwnerUserId, Tag
),
UserTopTagRanked as (
    select
        utt.UserId,
        utt.Tag,
        utt.TagCount,
        rank() over (partition by utt.UserId order by utt.TagCount desc) as TagRank
    from UserTopTags utt
),
UserTop3Tags as (
    select
        UserId,
        string_agg(Tag, ', ' order by TagCount desc) as TopTags
    from UserTopTagRanked
    where TagRank <= 3
    group by UserId
)
select
    rq.GlobalRank,
    rq.Id as QuestionId,
    rq.Title,
    rq.OwnerUserId,
    rq.OwnerName,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    rq.Tags,
    rq.AcceptedAnswerId,
    rq.AnswerCount,
    rq.AvgAnswerScore,
    rq.MaxAnswerScore,
    rq.AnsweredByRegisteredUsers,
    rq.CloseReason,
    rq.CloseDate,
    rq.UpVotes,
    rq.DownVotes,
    rq.Favorites,
    rq.CommentCount,
    urs.Reputation,
    urs.GoldBadges,
    urs.SilverBadges,
    urs.BronzeBadges,
    uas.QuestionsPosted,
    uas.AnswersPosted,
    uas.CommentsMade,
    uas.UpVotesGiven,
    uas.DownVotesGiven,
    uas.LastPostDate,
    uas.LastCommentDate,
    uas.LastVoteDate,
    ut3.TopTags,
    -- Complex string expression with NULL logic and conditional
    case
        when rq.CloseReason is not null then
            'Closed: ' || rq.CloseReason || ' on ' || to_char(rq.CloseDate, 'YYYY-MM-DD')
        when rq.AcceptedAnswerId is not null then
            'Accepted Answer ID: ' || rq.AcceptedAnswerId::text
        else
            'Open Question'
    end as StatusDescription,
    -- Window function example: percentile rank of question score within all questions
    percentile_cont(0.5) within group (order by rq.Score) over () as MedianScore,
    -- Correlated subquery: count of distinct users who answered this question
    (select count(distinct a.OwnerUserId) from Posts a where a.PostTypeId = 2 and a.ParentId = rq.Id and a.OwnerUserId is not null) as DistinctAnswerers,
    -- Outer join with recursive CTE to get related tags path (limited to 3 levels)
    (select string_agg(rth.TagName, ' > ') from RecursiveTagHierarchy rth where rth.TagName = (select unnest(string_to_array(substring(rq.Tags from 2 for length(rq.Tags)-2), '><')) limit 1)) as TagHierarchyPath
from RankedQuestions rq
left join UserReputationStats urs on urs.UserId = rq.OwnerUserId
left join UserActivitySummary uas on uas.UserId = rq.OwnerUserId
left join UserTop3Tags ut3 on ut3.UserId = rq.OwnerUserId
where rq.GlobalRank <= 100
order by rq.GlobalRank;