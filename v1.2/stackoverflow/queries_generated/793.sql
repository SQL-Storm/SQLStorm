-- {"query": "793.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1289} 
with RecursiveTagHierarchy as (
    select t.Id, t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, t.IsModeratorOnly, t.IsRequired, 0 as Level
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select t.Id, t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, t.IsModeratorOnly, t.IsRequired, r.Level + 1
    from Tags t
    join RecursiveTagHierarchy r on t.Id = r.Id and r.Level < 1
),
TopQuestions as (
    select p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags,
           u.DisplayName as OwnerName,
           row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as rn
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1 and p.CreationDate >= current_date - interval '365 days'
),
AnswerStats as (
    select a.ParentId as QuestionId,
           count(*) as TotalAnswers,
           avg(a.Score) as AvgAnswerScore,
           max(a.Score) as MaxAnswerScore,
           sum(case when a.Score > 5 then 1 else 0 end) as HighScoreAnswers
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
UserBadgeCounts as (
    select b.UserId,
           sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
           sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
           sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
CloseReasonsCount as (
    select ph.PostId,
           count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVotes,
           count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenVotes
    from PostHistory ph
    group by ph.PostId
),
RecentCommentsAgg as (
    select c.PostId,
           string_agg(distinct c.UserDisplayName || ': ' || left(c.Text, 30), ' | ' order by c.CreationDate desc) as RecentCommentsSnippet
    from Comments c
    where c.CreationDate > current_date - interval '90 days'
    group by c.PostId
),
PostWithLinks as (
    select p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags,
           pl.LinkTypeId, pl.RelatedPostId,
           lt.Name as LinkTypeName
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    where p.PostTypeId = 1
),
ComplexFilteredQuestions as (
    select tq.Id, tq.Title, tq.CreationDate, tq.Score, tq.ViewCount, tq.Tags, tq.OwnerName,
           as_.TotalAnswers, as_.AvgAnswerScore, as_.MaxAnswerScore, as_.HighScoreAnswers,
           ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges,
           cr.CloseVotes, cr.ReopenVotes,
           rc.RecentCommentsSnippet,
           count(distinct pwl.RelatedPostId) filter (where pwl.LinkTypeName = 'Duplicate') as DuplicateLinks,
           count(distinct pwl.RelatedPostId) filter (where pwl.LinkTypeName = 'Linked') as LinkedPosts
    from TopQuestions tq
    left join AnswerStats as_ on as_.QuestionId = tq.Id
    left join UserBadgeCounts ub on ub.UserId = (select Id from Users where DisplayName = tq.OwnerName limit 1)
    left join CloseReasonsCount cr on cr.PostId = tq.Id
    left join RecentCommentsAgg rc on rc.PostId = tq.Id
    left join PostWithLinks pwl on pwl.Id = tq.Id
    where (tq.Score > 10 or as_.AvgAnswerScore > 5 or ub.GoldBadges > 2)
      and (cr.CloseVotes is null or cr.CloseVotes < 3)
    group by tq.Id, tq.Title, tq.CreationDate, tq.Score, tq.ViewCount, tq.Tags, tq.OwnerName,
             as_.TotalAnswers, as_.AvgAnswerScore, as_.MaxAnswerScore, as_.HighScoreAnswers,
             ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges,
             cr.CloseVotes, cr.ReopenVotes,
             rc.RecentCommentsSnippet
),
RankedQuestions as (
    select *,
           rank() over (order by Score desc, ViewCount desc, TotalAnswers desc nulls last) as RankByScore
    from ComplexFilteredQuestions
)
select rq.RankByScore, rq.Id as QuestionId, rq.Title, rq.CreationDate, rq.Score, rq.ViewCount, rq.Tags,
       rq.OwnerName, rq.TotalAnswers, rq.AvgAnswerScore, rq.MaxAnswerScore, rq.HighScoreAnswers,
       rq.GoldBadges, rq.SilverBadges, rq.BronzeBadges,
       rq.CloseVotes, rq.ReopenVotes, rq.RecentCommentsSnippet,
       rq.DuplicateLinks, rq.LinkedPosts,
       rth.TagName,
       length(coalesce(rq.Title, '')) as TitleLength,
       case when rq.CloseVotes > 0 then 'Closed' else 'Open' end as Status,
       coalesce(rq.RecentCommentsSnippet, 'No recent comments') as CommentsSummary
from RankedQuestions rq
left join RecursiveTagHierarchy rth on rth.TagName = substring(rq.Tags from '<([^>]+)>')
where rq.RankByScore <= 50
order by rq.RankByScore, rq.CreationDate desc;