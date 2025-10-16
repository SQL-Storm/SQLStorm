-- {"query": "1031.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1753} 
with RecursiveBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        b.Class,
        count(b.Id) as BadgeCount
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, b.Class

    union all

    select
        rbc.UserId,
        rbc.DisplayName,
        rbc.Reputation,
        rbc.CreationDate,
        case when rbc.Class is null then 1 else rbc.Class + 1 end,
        0
    from RecursiveBadgeCounts rbc
    where rbc.Class < 3 or rbc.Class is null
),
UserPostStats as (
    select
        u.Id as UserId,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        avg(p.Score) filter (where p.PostTypeId in (1, 2)) as AvgPostScore,
        sum(coalesce(p.ViewCount,0)) filter (where p.PostTypeId = 1) as TotalQuestionViews
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id
),
TopTags as (
    select
        t.TagName,
        t.Count,
        t.IsModeratorOnly,
        t.IsRequired,
        p.Id as ExcerptPostId,
        p.Title as ExcerptTitle
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId
    where t.Count > 1000 -- Filter only popular tags
),
PostComments as (
    select
        p.Id as PostId,
        count(c.Id) as CommentCount,
        max(c.CreationDate) as LastCommentDate,
        string_agg(distinct c.UserDisplayName, ', ') filter (where c.UserDisplayName is not null) as Commenters
    from Posts p
    left join Comments c on c.PostId = p.Id
    group by p.Id
),
AnswerRanks as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    where a.PostTypeId = 2
),
QuestionDetails as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.AcceptedAnswerId,
        q.Score,
        q.ViewCount,
        q.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        u.Reputation as OwnerReputation,
        ps.CommentCount as QuestionCommentCount,
        ps.LastCommentDate as QuestionLastCommentDate,
        ps.Commenters as QuestionCommenters,
        (select count(*)
            from Posts a where a.ParentId = q.Id and a.PostTypeId = 2) as TotalAnswers,
        (select avg(a.Score)
            from Posts a where a.ParentId = q.Id and a.PostTypeId = 2) as AvgAnswerScore,
        ar.AnswerId,
        ar.AnswerRank
    from Posts q
    left join Users u on u.Id = q.OwnerUserId
    left join PostComments ps on ps.PostId = q.Id
    left join AnswerRanks ar on ar.QuestionId = q.Id and ar.AnswerRank = 1
    where q.PostTypeId = 1
      and q.CreationDate > current_date - interval '1 year'
),
DuplicatesAndLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    left join Posts p1 on p1.Id = pl.PostId
    left join Posts p2 on p2.Id = pl.RelatedPostId
    where lt.Name in ('Duplicate', 'Linked')
),
UserRecentActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        max(ph.CreationDate) as LastEditDate,
        max(v.CreationDate) as LastVoteDate,
        max(c.CreationDate) as LastCommentDate,
        coalesce(max(ph.CreationDate), max(v.CreationDate), max(c.CreationDate), u.LastAccessDate) as LastActivity
    from Users u
    left join PostHistory ph on ph.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName
),
UserEngagement as (
    select
        ura.UserId,
        ura.DisplayName,
        urc.LastEditDate,
        urc.LastVoteDate,
        urc.LastCommentDate,
        urc.LastActivity,
        rbc.Class as BadgeClass,
        rbc.BadgeCount,
        ups.QuestionCount,
        ups.AnswerCount,
        ups.AvgPostScore,
        ups.TotalQuestionViews
    from UserRecentActivity urc
    join RecursiveBadgeCounts rbc on rbc.UserId = urc.UserId
    join UserPostStats ups on ups.UserId = urc.UserId
    join (select distinct UserId, DisplayName from Users) ura on ura.UserId = urc.UserId
    where rbc.Class is not null
),
FinalResults as (
    select
        ue.UserId,
        ue.DisplayName,
        ue.BadgeClass,
        ue.BadgeCount,
        ue.QuestionCount,
        ue.AnswerCount,
        ue.AvgPostScore,
        ue.TotalQuestionViews,
        ue.LastActivity,
        q.QuestionId,
        q.Title,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.TotalAnswers,
        q.AvgAnswerScore,
        q.AnswerId,
        q.AnswerRank,
        dt.LinkTypeName,
        dt.PostTitle,
        dt.RelatedPostTitle,
        tt.TagName,
        tt.Count as TagCount,
        tt.IsModeratorOnly,
        tt.IsRequired,
        tt.ExcerptTitle
    from UserEngagement ue
    left join QuestionDetails q on q.OwnerUserId = ue.UserId
    left join DuplicatesAndLinks dt on dt.PostId = q.QuestionId
    left join LATERAL (
        -- Find popular tags from question tags
        select t.*
        from TopTags t
        where q.Tags is not null
          and (
              position('<' || t.TagName || '>' in q.Tags) > 0
              or q.Tags like '%>' || t.TagName || '<%'
          )
        limit 1
    ) tt on true
    where ue.BadgeCount > 5
      and ue.LastActivity > current_date - interval '6 months'
    order by ue.BadgeClass asc, ue.BadgeCount desc, ue.LastActivity desc
    limit 100
)
select
    UserId,
    DisplayName,
    BadgeClass,
    BadgeCount,
    QuestionCount,
    AnswerCount,
    round(COALESCE(AvgPostScore,0),2) as AvgPostScore,
    TotalQuestionViews,
    LastActivity,
    QuestionId,
    left(Title, 100) as QuestionTitleSnippet,
    QuestionScore,
    QuestionViews,
    TotalAnswers,
    round(COALESCE(AvgAnswerScore,0),2) as AvgAnswerScore,
    AnswerId as TopAnswerId,
    AnswerRank,
    coalesce(LinkTypeName, 'None') as PostLinkType,
    left(PostTitle, 50) as PostLinkTitleSnippet,
    left(RelatedPostTitle, 50) as RelatedPostTitleSnippet,
    TagName,
    TagCount,
    coalesce(IsModeratorOnly::text, 'False') as IsModeratorOnly,
    coalesce(IsRequired::text, 'False') as IsRequired,
    left(ExcerptTitle, 50) as TagExcerptTitleSnippet
from FinalResults;