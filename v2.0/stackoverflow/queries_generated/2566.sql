-- {"query": "2566.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1452} 
with RecursiveTagCounts as (
    select 
        t.Id as TagId,
        t.TagName,
        p.Id as PostId,
        p.CreationDate,
        u.Id as OwnerUserId,
        u.DisplayName,
        row_number() over(partition by t.Id order by p.CreationDate desc) as rn
    from Tags t
    join Posts p on p.Tags like '%' || t.TagName || '%'
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1
),
RecentTagPosts as (
    select TagId, TagName, PostId, CreationDate, OwnerUserId, DisplayName
    from RecursiveTagCounts
    where rn <= 10
),
UserBadgeCounts as (
    select 
        b.UserId,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
PostScoreWindows as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        users.DisplayName,
        avg(p.Score) over(partition by p.OwnerUserId order by p.CreationDate rows between unbounded preceding and current row) as AvgScorePerUser,
        rank() over(partition by p.OwnerUserId order by p.Score desc) as ScoreRankPerUser
    from Posts p 
    left join Users users on p.OwnerUserId = users.Id
    where p.PostTypeId = 1 and p.Score is not null
),
ClosedQuestionsWithReasons as (
    select 
        ph.PostId,
        pr.Name as CloseReasonName,
        ph.CreationDate as CloseDate,
        ph.UserId as CloseUserId,
        u.DisplayName as CloseUserName
    from PostHistory ph
    join CloseReasonTypes pr on cast(ph.Comment as int) = pr.Id and ph.PostHistoryTypeId = 10
    left join Users u on ph.UserId = u.Id
),
UserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as QuestionCount,
        count(distinct a.Id) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        coalesce(sum(vt.ScoreVotes),0) as TotalVotes,
        coalesce(bc.GoldBadges,0) as GoldBadges,
        coalesce(bc.SilverBadges,0) as SilverBadges,
        coalesce(bc.BronzeBadges,0) as BronzeBadges,
        row_number() over(order by count(distinct p.Id) desc, count(distinct a.Id) desc) as ActivityRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    left join Comments c on c.UserId = u.Id
    left join (
        select v.UserId, sum(case when vt.Name in ('UpMod','DownMod') then 1 else 0 end) as ScoreVotes
        from Votes v
        join VoteTypes vt on v.VoteTypeId = vt.Id
        group by v.UserId
    ) vt on vt.UserId = u.Id
    left join UserBadgeCounts bc on bc.UserId = u.Id
    group by u.Id, u.DisplayName, bc.GoldBadges, bc.SilverBadges, bc.BronzeBadges
),
DuplicateLinkedPosts as (
    select pl.PostId, pl.RelatedPostId, pl.CreationDate, lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    where lt.Name = 'Duplicate'
),
CorrelatedUserAnswers as (
    select a.Id as AnswerId, a.ParentId as QuestionId, a.Score, a.CreationDate, a.OwnerUserId,
      (select count(*) from Comments c where c.PostId = a.Id) as AnswerCommentCount,
      (select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 2) as UpVoteCount,
      (select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 3) as DownVoteCount
    from Posts a
    where a.PostTypeId = 2
),
FilteredAnswers as (
    select 
        cua.AnswerId,
        cua.QuestionId,
        cua.Score,
        cua.CreationDate,
        cua.OwnerUserId,
        cua.AnswerCommentCount,
        cua.UpVoteCount,
        cua.DownVoteCount
    from CorrelatedUserAnswers cua
    where cua.Score > 5 or cua.UpVoteCount - cua.DownVoteCount > 10
),
AnswerStatistics as (
    select 
        fa.OwnerUserId,
        count(*) as HighScoreAnswerCount,
        avg(fa.Score) as AvgHighScoreAnswer,
        max(fa.UpVoteCount) as MaxUpVotes,
        min(fa.DownVoteCount) as MinDownVotes
    from FilteredAnswers fa
    group by fa.OwnerUserId
)
select 
    ua.UserId,
    ua.DisplayName,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.CommentCount,
    ua.TotalVotes,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.ActivityRank,
    coalesce(asg.HighScoreAnswerCount,0) as HighScoreAnswerCount,
    coalesce(asg.AvgHighScoreAnswer,0) as AvgHighScoreAnswer,
    coalesce(asg.MaxUpVotes,0) as MaxUpVotesOnAnswer,
    coalesce(asg.MinDownVotes,0) as MinDownVotesOnAnswer,
    (select count(distinct dlp.PostId) from DuplicateLinkedPosts dlp join Posts p on p.Id = dlp.PostId where p.OwnerUserId = ua.UserId) as UserDuplicatePostsCount,
    (select count(*) from ClosedQuestionsWithReasons cqr where cqr.CloseUserId = ua.UserId and cqr.CloseDate > (current_date - interval '365 days')) as CloseVotesInLastYear,
    (select string_agg(distinct rt.TagName, ', ' order by rt.TagName) from RecentTagPosts rt where rt.OwnerUserId = ua.UserId) as RecentTagsUsed
from UserActivity ua
left join AnswerStatistics asg on asg.OwnerUserId = ua.UserId
where ua.QuestionCount > 5
order by ua.ActivityRank
limit 100;