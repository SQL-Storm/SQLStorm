-- {"query": "319.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1739} 
with RecursiveTagHierarchy as (
    select t.Id, t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, t.IsModeratorOnly, t.IsRequired, 1 as Level
    from Tags t
    where t.IsRequired = 1
    union all
    select t2.Id, t2.TagName, t2.Count, t2.ExcerptPostId, t2.WikiPostId, t2.IsModeratorOnly, t2.IsRequired, r.Level + 1
    from Tags t2
    inner join RecursiveTagHierarchy r on t2.Id = r.Id + 1 and t2.IsModeratorOnly = 0
),
UserBadgeCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        coalesce(sum(case when b.TagBased = 1 then 1 else 0 end),0) as TagBasedBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostScoreRanks as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc nulls last) as ScoreRank,
        rank() over (partition by p.PostTypeId order by p.Score desc) as ScoreDenseRank,
        count(*) over (partition by p.PostTypeId) as TotalPostsOfType
    from Posts p
    where p.PostTypeId in (1,2)
),
TopPostsWithComments as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.ScoreRank,
        p.ScoreDenseRank,
        p.TotalPostsOfType,
        coalesce(c.CommentCount, 0) as CommentCount,
        coalesce(vc.UpVotes, 0) as UpVotes,
        coalesce(vc.DownVotes, 0) as DownVotes
    from PostScoreRanks p
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) c on c.PostId = p.Id
    left join (
        select 
            v.PostId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        inner join VoteTypes vt on vt.Id = v.VoteTypeId
        group by v.PostId
    ) vc on vc.PostId = p.Id
    where p.ScoreRank <= 100
),
AcceptedAnswerStats as (
    select 
        q.Id as QuestionId,
        q.AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.ViewCount as AcceptedAnswerViewCount,
        a.OwnerUserId as AcceptedAnswerOwnerUserId
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    where q.PostTypeId = 1
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
        max(p.CreationDate) as LastPostDate,
        min(p.CreationDate) as FirstPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),
DuplicateLinks as (
    select 
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        pl.CreationDate
    from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    inner join Posts p1 on p1.Id = pl.PostId
    inner join Posts p2 on p2.Id = pl.RelatedPostId
),
RecentEditsWithCloseInfo as (
    select 
        ph.Id,
        ph.PostId,
        ph.PostHistoryTypeId,
        p.Title,
        ph.CreationDate,
        ph.UserId,
        u.DisplayName as EditorName,
        ph.Comment,
        crt.Name as CloseReasonName
    from PostHistory ph
    left join Posts p on p.Id = ph.PostId
    left join Users u on u.Id = ph.UserId
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int) and ph.PostHistoryTypeId = 10
    where ph.CreationDate > current_date - interval '30 days'
),
UserReputationWindow as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        sum(coalesce(p.Score,0)) over (order by u.Reputation desc rows between unbounded preceding and current row) as CumulativeReputation,
        row_number() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
CombinedResults as (
    select 
        t.Id as TagId,
        t.TagName,
        t.Count as TagCount,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        ubc.TagBasedBadges,
        ta.QuestionId,
        ta.AcceptedAnswerId,
        ta.AcceptedAnswerScore,
        ta.AcceptedAnswerViewCount,
        ta.AcceptedAnswerOwnerUserId,
        upc.Id as PostId,
        upc.PostTypeId,
        upc.Score,
        upc.ViewCount,
        upc.CommentCount,
        upc.UpVotes,
        upc.DownVotes,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.CommentsMade,
        ua.UpVotesGiven,
        ua.DownVotesGiven,
        ua.LastPostDate,
        ua.FirstPostDate,
        rl.PostTitle as DuplicatePostTitle,
        rl.RelatedPostTitle as DuplicateRelatedPostTitle,
        re.CreationDate as RecentEditDate,
        re.EditorName,
        re.CloseReasonName,
        urw.Reputation,
        urw.CumulativeReputation,
        urw.ReputationRank
    from RecursiveTagHierarchy t
    left join UserBadgeCounts ubc on ubc.UserId = (select OwnerUserId from Posts where Id = t.ExcerptPostId limit 1)
    left join AcceptedAnswerStats ta on ta.QuestionId = t.ExcerptPostId
    left join TopPostsWithComments upc on upc.Id = t.ExcerptPostId
    left join UserActivitySummary ua on ua.UserId = ubc.UserId
    left join DuplicateLinks rl on rl.PostId = t.ExcerptPostId
    left join RecentEditsWithCloseInfo re on re.PostId = t.ExcerptPostId
    left join UserReputationWindow urw on urw.Id = ubc.UserId
    where t.Level <= 3
    order by t.Count desc nulls last, ubc.GoldBadges desc nulls last, upc.Score desc nulls last
    limit 50
)
select * from CombinedResults;