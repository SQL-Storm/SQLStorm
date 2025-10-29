-- {"query": "2782.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1748} 
with RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        p.AnswerCount,
        dense_rank() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate) as ScoreRank,
        lag(p.Score) over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate) as NextScore
    from Posts p
    where p.PostTypeId in (1, 2) -- questions and answers
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
QuestionsWithDuplicates as (
    select distinct
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.OwnerUserId,
        dup.RelatedPostId as DuplicateOf
    from Posts q
    left join PostLinks dup on dup.PostId = q.Id and dup.LinkTypeId = 3 -- duplicates
    where q.PostTypeId = 1
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        coalesce(ub.GoldBadges,0) as GoldBadges,
        coalesce(ub.SilverBadges,0) as SilverBadges,
        coalesce(ub.BronzeBadges,0) as BronzeBadges,
        coalesce(ub.TotalBadges,0) as TotalBadges,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        count(distinct c.Id) as CommentsCount
    from Users u
    left join Badges b on b.UserId = u.Id
    left join UserBadgeCounts ub on ub.UserId = u.Id
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by 
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location,
        ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ub.TotalBadges
),
TopPostsWithVotes as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.CreationDate,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end), 0) as UpVotes,
        coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end), 0) as DownVotes,
        (coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end), 0) - coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end), 0)) as NetVotes
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId, p.OwnerUserId, p.Title, p.Score, p.CreationDate
    having p.PostTypeId = 1 and p.Score > 50
),
LastActivityRanks as (
    select
        u.Id as UserId,
        p.Id as PostId,
        p.Title,
        p.CreationDate,
        p.LastActivityDate,
        rank() over (partition by u.Id order by p.LastActivityDate desc) as ActivityRank
    from Users u
    join Posts p on p.OwnerUserId = u.Id
    where p.LastActivityDate is not null
),
QuestionsWithCloseInfo as (
    select
        p.Id,
        p.Title,
        cht.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10 -- Post Closed
    left join CloseReasonTypes cht on ph.Comment = cast(cht.Id as varchar)
    where p.PostTypeId = 1
),
UserLinkNetworks as (
    select 
        u1.Id as UserId,
        u2.Id as LinkedUserId,
        count(*) as LinkCount
    from Users u1
    join Posts p1 on p1.OwnerUserId = u1.Id and p1.PostTypeId = 1
    join PostLinks l on l.PostId = p1.Id and l.LinkTypeId = 1
    join Posts p2 on p2.Id = l.RelatedPostId and p2.OwnerUserId is not null
    join Users u2 on u2.Id = p2.OwnerUserId
    where u1.Id != u2.Id
    group by u1.Id, u2.Id
),
UserNetworkSummary as (
    select
        UserId,
        count(distinct LinkedUserId) as DistinctLinkedUsers,
        sum(LinkCount) as TotalLinks
    from UserLinkNetworks
    group by UserId
)
select
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.Location,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.TotalBadges,
    ua.QuestionsCount,
    ua.AnswersCount,
    ua.CommentsCount,
    coalesce(uns.DistinctLinkedUsers,0) as DistinctLinkedUsers,
    coalesce(uns.TotalLinks,0) as TotalLinks,
    count(distinct qdu.QuestionId) filter (where qdu.DuplicateOf is not null) as DuplicatedQuestionsCount,
    (select avg(NetVotes) from TopPostsWithVotes tp where tp.OwnerUserId = ua.UserId) as AvgNetVotesOnTopQuestions,
    (select string_agg(distinct coalesce(crt.Name, 'N/A'), ', ') 
        from QuestionsWithCloseInfo qci 
        left join CloseReasonTypes crt on cast(qci.CloseReasonName as varchar) = crt.Name
        where qci.Id in (select Id from Posts where OwnerUserId = ua.UserId and PostTypeId = 1)) as CloseReasons,
    (select count(*) 
        from Posts p 
        where p.OwnerUserId = ua.UserId 
        and p.PostTypeId = 1 
        and p.AcceptedAnswerId is not null) as QuestionsWithAcceptedAnswer,
    (select count(*) 
        from Posts p 
        where p.OwnerUserId = ua.UserId 
        and p.PostTypeId = 2 
        and p.ParentId is not null 
        and p.Score > 10) as HighlyRatedAnswers,
    (select max(ScoreRank) 
        from RankedPosts rp 
        where rp.OwnerUserId = ua.UserId 
        and rp.PostTypeId = 1) as MaxQuestionScoreRank,
    (select max(ScoreRank) 
        from RankedPosts rp 
        where rp.OwnerUserId = ua.UserId 
        and rp.PostTypeId = 2) as MaxAnswerScoreRank,
    (select string_agg(distinct Tags, ' | ') from Posts p where p.OwnerUserId = ua.UserId and p.PostTypeId=1 and p.Tags is not null) as AllQuestionTags
from UserActivity ua
left join UserNetworkSummary uns on uns.UserId = ua.UserId
left join QuestionsWithDuplicates qdu on qdu.OwnerUserId = ua.UserId
where ua.Reputation > 1000
order by ua.Reputation desc
limit 50;