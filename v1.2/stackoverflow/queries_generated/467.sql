-- {"query": "467.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1778} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsRequired = 1

    union all

    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        r.Level + 1,
        r.Path || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.IsRequired = 1 and t.Id <> r.Id and not t.TagName = any(r.Path)
    where r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
PostScoreRanks as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as ScoreRank,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc) as ScoreDenseRank,
        lag(p.Score) over (partition by p.PostTypeId order by p.Score desc) as PrevScore,
        lead(p.Score) over (partition by p.PostTypeId order by p.Score desc) as NextScore
    from Posts p
    where p.Score is not null
),
TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerOwnerUserId,
        a.CreationDate as AnswerCreation,
        a.Score as AnswerScore,
        a.ParentId,
        a.Body,
        u.DisplayName as QuestionOwnerName,
        ua.DisplayName as AnswerOwnerName
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = q.OwnerUserId
    left join Users ua on ua.Id = a.OwnerUserId
    where q.PostTypeId = 1
      and q.Score > (select avg(Score) from Posts where PostTypeId = 1)
),
CloseReasonCounts as (
    select
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
    group by ph.Comment, crt.Name
),
UserActivityWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(c.Id) as CommentsMade,
        sum(v.VoteTypeId = 2)::int as UpVotesReceived,
        sum(v.VoteTypeId = 3)::int as DownVotesReceived,
        row_number() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
UserRecentActivity as (
    select
        ua.Id,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.CommentsMade,
        ua.UpVotesReceived,
        ua.DownVotesReceived,
        ua.ReputationRank,
        max(p.CreationDate) filter (where p.OwnerUserId = ua.Id) as LastPostDate,
        max(c.CreationDate) filter (where c.UserId = ua.Id) as LastCommentDate,
        greatest(
            coalesce(max(p.CreationDate) filter (where p.OwnerUserId = ua.Id), '1900-01-01'::timestamp),
            coalesce(max(c.CreationDate) filter (where c.UserId = ua.Id), '1900-01-01'::timestamp)
        ) as LastActivityDate
    from UserActivityWindow ua
    left join Posts p on p.OwnerUserId = ua.Id
    left join Comments c on c.UserId = ua.Id
    group by ua.Id, ua.DisplayName, ua.Reputation, ua.QuestionsPosted, ua.AnswersPosted, ua.CommentsMade, ua.UpVotesReceived, ua.DownVotesReceived, ua.ReputationRank
),
HighImpactPosts as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Tags,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        (select count(distinct ph.UserId) from PostHistory ph where ph.PostId = p.Id) as EditorsCount
    from Posts p
    where p.Score > 50
      and p.PostTypeId in (1, 2)
),
CombinedResults as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.CommentsMade,
        ua.UpVotesReceived,
        ua.DownVotesReceived,
        ua.LastActivityDate,
        hp.Id as HighImpactPostId,
        hp.Title as HighImpactPostTitle,
        hp.Score as HighImpactPostScore,
        hp.ViewCount as HighImpactPostViews,
        hp.Tags as HighImpactPostTags,
        cr.CloseReasonName,
        cr.CloseCount
    from UserRecentActivity ua
    left join Users u on u.Id = ua.Id
    left join UserBadgeCounts ub on ub.UserId = u.Id
    left join HighImpactPosts hp on hp.OwnerUserId = u.Id
    left join PostHistory ph on ph.PostId = hp.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonCounts cr on cr.CloseReasonId = ph.Comment
    where ua.ReputationRank <= 100
)
select
    crs.UserId,
    crs.DisplayName,
    crs.Reputation,
    crs.GoldBadges,
    crs.SilverBadges,
    crs.BronzeBadges,
    crs.QuestionsPosted,
    crs.AnswersPosted,
    crs.CommentsMade,
    crs.UpVotesReceived,
    crs.DownVotesReceived,
    to_char(crs.LastActivityDate, 'YYYY-MM-DD HH24:MI:SS') as LastActivity,
    crs.HighImpactPostId,
    left(crs.HighImpactPostTitle, 100) as HighImpactPostTitle,
    crs.HighImpactPostScore,
    crs.HighImpactPostViews,
    coalesce(array_to_string(string_to_array(crs.HighImpactPostTags, '><'), ', '), 'No Tags') as ParsedTags,
    crs.CloseReasonName,
    crs.CloseCount
from CombinedResults crs
where crs.HighImpactPostScore is not null
order by crs.Reputation desc, crs.HighImpactPostScore desc
limit 50;