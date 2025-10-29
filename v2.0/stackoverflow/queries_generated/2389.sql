-- {"query": "2389.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1926} 

with RecursivePopularTags as (
    select t.Id, t.TagName, t.Count,
           row_number() over (order by t.Count desc) as rn
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
),
TopTags as (
    select Id, TagName from RecursivePopularTags where rn <= 10
),
UserReputationStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        coalesce(sum(case when p.PostTypeId = 1 then p.Score else 0 end),0) as QuestionScoreSum,
        coalesce(sum(case when p.PostTypeId = 2 then p.Score else 0 end),0) as AnswerScoreSum,
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
        rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
LatestPostHistory AS (
    select ph.PostId, ph.PostHistoryTypeId, ph.CreationDate,
           row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6) -- edits to Title/Body/Tags
),
PostTagExploded AS (
    select p.Id as PostId, unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as Tag
    from Posts p
    where p.Tags is not null and p.PostTypeId = 1
),
FilteredPosts AS (
    select p.Id, p.Title, p.Score, p.ViewCount, p.OwnerUserId, p.CreationDate, p.AcceptedAnswerId,
           array_agg(distinct pt.Tag) filter (where pt.Tag in (select TagName from TopTags)) as PopularTags,
           count(c.Id) as CommentCount,
           case when p.ClosedDate is not null then 1 else 0 end as IsClosed
    from Posts p
    left join PostTagExploded pt on pt.PostId = p.Id
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.Score, p.ViewCount, p.OwnerUserId, p.CreationDate, p.AcceptedAnswerId, p.ClosedDate
),
AvgAnswerScores AS (
    select ParentId,
           avg(coalesce(Score,0)) as AvgAnswerScore,
           count(*) as AnswerCount
    from Posts
    where PostTypeId = 2
    group by ParentId
),
Duplicates AS (
    select pl.PostId, pl.RelatedPostId,
           max(case when lt.Name = 'Duplicate' then 1 else 0 end) as IsDuplicateLink
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId, pl.RelatedPostId
),
QuestionsWithDuplicates AS (
    select p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount,
           dup.RelatedPostId, dup.IsDuplicateLink
    from Posts p
    left join Duplicates dup on dup.PostId = p.Id
    where p.PostTypeId = 1 and dup.IsDuplicateLink = 1
),
UserActivityRanges AS (
    select OwnerUserId as UserId,
           min(CreationDate) as FirstPostDate,
           max(CreationDate) as LastPostDate,
           count(*) as PostsCount,
           count(distinct case when PostTypeId =1 then Id end) as QuestionsCount,
           count(distinct case when PostTypeId =2 then Id end) as AnswersCount
    from Posts
    where OwnerUserId is not null
    group by OwnerUserId
),
UserVotesSummary AS (
    select v.UserId,
           count(*) filter (where vt.Name = 'UpMod') as UpVotesGiven,
           count(*) filter (where vt.Name = 'DownMod') as DownVotesGiven,
           count(*) filter (where vt.Name = 'AcceptedByOriginator') as AcceptedVotesGiven
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    where v.UserId is not null
    group by v.UserId
),
UserStats AS (
    select urs.UserId, urs.DisplayName, urs.Reputation, urs.GoldBadges, urs.SilverBadges, urs.BronzeBadges,
           ar.FirstPostDate, ar.LastPostDate, ar.PostsCount, ar.QuestionsCount, ar.AnswersCount,
           coalesce(uv.UpVotesGiven,0) as UpVotesGiven,
           coalesce(uv.DownVotesGiven,0) as DownVotesGiven,
           coalesce(uv.AcceptedVotesGiven,0) as AcceptedVotesGiven,
           (ars.QuestionScoreSum + ars.AnswerScoreSum) as TotalPostScore
    from UserReputationStats urs
    left join UserActivityRanges ar on ar.UserId = urs.UserId
    left join UserVotesSummary uv on uv.UserId = urs.UserId
    left join (
        select OwnerUserId,
               sum(case when PostTypeId=1 then Score else 0 end) as QuestionScoreSum,
               sum(case when PostTypeId=2 then Score else 0 end) as AnswerScoreSum
        from Posts
        group by OwnerUserId
    ) ars on ars.OwnerUserId = urs.UserId
),
RankedQuestions AS (
    select fp.*,
           coalesce(av.AvgAnswerScore, 0) as AvgAnswerScore,
           rank() over (order by fp.Score desc, fp.ViewCount desc) as ScoreRank,
           row_number() over (partition by fp.OwnerUserId order by fp.Score desc) as UserTopQuestionRank,
           count(distinct c.Id) filter (where c.CreationDate > fp.CreationDate) over (partition by fp.Id) as CommentsAfterCreation
    from FilteredPosts fp
    left join AvgAnswerScores av on av.ParentId = fp.Id
    left join Comments c on c.PostId = fp.Id
)
select
    rq.Id as QuestionId,
    rq.Title,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    rq.IsClosed,
    rq.AnswerCount,
    rq.PopularTags,
    rq.CommentCount,
    rq.AvgAnswerScore,
    rq.ScoreRank,
    rq.UserTopQuestionRank,
    us.DisplayName as OwnerDisplayName,
    us.Reputation as OwnerReputation,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.PostsCount,
    us.QuestionsCount,
    us.AnswersCount,
    us.UpVotesGiven,
    us.DownVotesGiven,
    us.AcceptedVotesGiven,
    us.TotalPostScore,
    phlt.Text as LatestEditSummary,
    -- Correlated subquery to get number of distinct users who commented on the question
    (
        select count(distinct coalesce(cu.Id, -1))
        from Comments cm
        left join Users cu on cu.Id = cm.UserId
        where cm.PostId = rq.Id
    ) as DistinctCommentersCount,
    -- Window function calculation: cumulative sum of scores of questions created before current question for the same user
    sum(rq.Score) over (partition by rq.OwnerUserId order by rq.CreationDate rows between unbounded preceding and current row) as CumulativeUserScore,
    -- Complicated predicate using NULL logic and string expressions
    case
        when rq.Title is null or length(trim(rq.Title)) = 0 then 'No Title'
        when rq.Title like '%error%' or rq.Title ilike '%exception%' then 'Contains Error Keywords'
        when rq.IsClosed = 1 then 'Closed Question'
        else 'Open'
    end as QuestionStatus,
    -- Set operation example: union of user badges names with recent badge names (last 30 days)
    (
        select string_agg(distinct b.Name, ', ' order by b.Name)
        from Badges b
        where b.UserId = us.UserId
          and b.Date >= current_date - interval '30 days'
    ) as RecentBadgeNames
from RankedQuestions rq
join UserStats us on us.UserId = rq.OwnerUserId
left join LatestPostHistory phlt on phlt.PostId = rq.Id and phlt.rn = 1
where rq.Score > 5
  and (rq.ViewCount > 1000 or rq.AnswerCount > 3)
order by rq.ScoreRank
limit 100;
